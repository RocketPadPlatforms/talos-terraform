variable "addons" {
  description = <<-EOT
    Optional cluster addons, installed as Talos inline manifests on the
    control planes and kept in sync with `talosctl upgrade-k8s` (see the
    manifests_sync_command output). Each addon is an object with `enabled`
    plus its own settings. metrics_server also enables kubelet_cert_approver.
    control_plane_metrics exposes etcd, controller-manager and scheduler
    metrics with discovery Services; a firewall rule limits the ports to
    node IPs plus allowed_subnets (default: the Talos pod CIDR).
  EOT
  type = object({
    kubelet_cert_approver = optional(object({
      enabled = optional(bool, false)
    }), {})
    metrics_server = optional(object({
      enabled = optional(bool, false)
    }), {})
    local_path_provisioner = optional(object({
      enabled               = optional(bool, false)
      default_storage_class = optional(bool, false)
    }), {})
    control_plane_metrics = optional(object({
      enabled         = optional(bool, false)
      allowed_subnets = optional(list(string), ["10.244.0.0/16"])
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in var.addons.control_plane_metrics.allowed_subnets : can(cidrhost(s, 0))])
    error_message = "addons.control_plane_metrics.allowed_subnets must be CIDR prefixes, e.g. 10.244.0.0/16."
  }
}

locals {
  // metrics-server can only verify kubelet certificates that the approver signed.
  kubelet_cert_approver_enabled = var.addons.kubelet_cert_approver.enabled || var.addons.metrics_server.enabled

  addon_manifests = merge(
    local.kubelet_cert_approver_enabled ? {
      "kubelet-serving-cert-approver" = file("${path.module}/deps/vendor/addons/kubelet-serving-cert-approver/deploy/standalone-install.yaml")
    } : {},
    var.addons.metrics_server.enabled ? {
      "metrics-server" = file("${path.module}/deps/vendor/addons/metrics-server/components.yaml")
    } : {},
    var.addons.local_path_provisioner.enabled ? {
      "local-path-provisioner" = local.local_path_provisioner_manifest
    } : {},
    var.addons.control_plane_metrics.enabled ? {
      "control-plane-metrics" = local.control_plane_metrics_manifest
    } : {},
  )

  // etcd is not a pod: select the host-network controller-manager pods, which
  // run on every control plane, so the endpoints follow the nodes.
  control_plane_metrics_manifest = join("---\n", [
    for name, s in {
      "kube-controller-manager" = { app = "kube-controller-manager", port = 10257, port_name = "https-metrics", component = "kube-controller-manager" }
      "kube-scheduler"          = { app = "kube-scheduler", port = 10259, port_name = "https-metrics", component = "kube-scheduler" }
      "kube-etcd"               = { app = "etcd", port = 2381, port_name = "http-metrics", component = "kube-controller-manager" }
      } : yamlencode({
        apiVersion = "v1"
        kind       = "Service"
        metadata = {
          name      = "${name}-prometheus-discovery"
          namespace = "kube-system"
          labels    = { "app.kubernetes.io/name" = s.app }
        }
        spec = {
          clusterIP = "None"
          selector  = { component = s.component }
          ports     = [{ name = s.port_name, port = s.port, targetPort = s.port, protocol = "TCP" }]
        }
    })
  ])

  local_path_provisioner_path = "/var/mnt/local-path-provisioner"
  local_path_helper_image     = "docker.io/library/busybox:1.38.0@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4"

  local_path_provisioner_documents = [
    for d in split("\n---\n", file("${path.module}/deps/vendor/addons/local-path-provisioner/deploy/local-path-storage.yaml")) :
    yamldecode(d) if trimspace(d) != ""
  ]

  // Talos only allows writes below /var/mnt and enforces pod security.
  local_path_provisioner_manifest = join("---\n", [
    for doc in local.local_path_provisioner_documents : yamlencode(merge(doc, lookup({
      ConfigMap = {
        data = merge(try(doc.data, {}), {
          "config.json" = jsonencode({
            nodePathMap = [{
              node  = "DEFAULT_PATH_FOR_NON_LISTED_NODES"
              paths = [local.local_path_provisioner_path]
            }]
          })
          "helperPod.yaml" = replace(try(doc.data["helperPod.yaml"], ""), "image: docker.io/library/busybox\n", "image: ${local.local_path_helper_image}\n")
        })
      }
      Namespace = {
        metadata = merge(doc.metadata, {
          labels = merge(try(doc.metadata.labels, {}), { "pod-security.kubernetes.io/enforce" = "privileged" })
        })
      }
      StorageClass = {
        metadata = merge(doc.metadata, var.addons.local_path_provisioner.default_storage_class ? {
          annotations = merge(try(doc.metadata.annotations, {}), { "storageclass.kubernetes.io/is-default-class" = "true" })
        } : {})
      }
    }, doc.kind, {})))
  ])

  addon_patches_all = var.addons.local_path_provisioner.enabled ? [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "directory"
    })
  ] : []

  etcd_metrics_args = { "listen-metrics-urls" = "http://0.0.0.0:2381" }

  addon_patches_controlplane = concat([
    for name in ["kubelet-serving-cert-approver", "metrics-server", "local-path-provisioner", "control-plane-metrics"] : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeInlineManifestConfig"
      name       = name
      manifest   = local.addon_manifests[name]
    }) if contains(keys(local.addon_manifests), name)
    ], var.addons.control_plane_metrics.enabled ? [
    // Talos rejects .cluster.* next to the generated document of the same
    // component; etcd got EtcdMemberConfig with the Talos 1.15 contract.
    strcontains(data.talos_machine_configuration.controlplane.machine_configuration, "kind: EtcdMemberConfig")
    ? yamlencode({ apiVersion = "v1alpha1", kind = "EtcdMemberConfig", extraArgs = local.etcd_metrics_args })
    : yamlencode({ cluster = { etcd = { extraArgs = local.etcd_metrics_args } } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeControllerManagerConfig", extraArgs = { "bind-address" = "0.0.0.0" } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeSchedulerConfig", extraArgs = { "bind-address" = "0.0.0.0" } }),
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "NetworkRuleConfig"
      name         = "control-plane-metrics-ingress"
      portSelector = { ports = [2381, 10257, 10259], protocol = "tcp" }
      ingress = [
        for subnet in concat(
          [for n in values(local.all_nodes) : "${n.ip_address}/${strcontains(n.ip_address, ":") ? 128 : 32}"],
          var.addons.control_plane_metrics.allowed_subnets
        ) : { subnet = subnet }
      ]
    }),
  ] : [])
}
