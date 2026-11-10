variable "addons" {
  description = <<-EOT
    Optional cluster addons, installed as Talos inline manifests on the
    control planes and kept in sync with `talosctl upgrade-k8s` (see the
    manifests_sync_command output). Each addon is an object with `enabled`
    plus its own settings. metrics_server also enables kubelet_cert_approver.
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
  })
  default  = {}
  nullable = false
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
  )

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

  addon_patches_controlplane = [
    for name in ["kubelet-serving-cert-approver", "metrics-server", "local-path-provisioner"] : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeInlineManifestConfig"
      name       = name
      manifest   = local.addon_manifests[name]
    }) if contains(keys(local.addon_manifests), name)
  ]
}
