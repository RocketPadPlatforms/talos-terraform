variable "cni" {
  description = <<-EOT
    The cluster CNI. `name` is `flannel` (Talos built-in, configured via
    config_patches) or `cilium` (installed from the vendored Helm chart as a
    Talos inline manifest, replacing Flannel and kube-proxy). For cilium,
    each `configuration` entry is a YAML document of Helm values applied on
    top of the module's base values. Do not change `name` on a running
    cluster.
  EOT
  type = object({
    name          = optional(string, "flannel")
    configuration = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["flannel", "cilium"], var.cni.name)
    error_message = "cni.name must be 'flannel' or 'cilium'."
  }

  validation {
    condition     = var.cni.name != "flannel" || length(var.cni.configuration) == 0
    error_message = "cni.configuration is not supported for flannel; use config_patches with a KubeFlannelCNIConfig document instead."
  }
}

locals {
  cilium_base_values = {
    ipam                 = { mode = "kubernetes" }
    kubeProxyReplacement = true
    securityContext = {
      capabilities = {
        ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
        cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
      }
    }
    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }
    // KubePrism: the API server on every node, without a load balancer.
    k8sServiceHost = "localhost"
    k8sServicePort = 7445
    // The chart's default ("helm") generates new certificates on every render.
    hubble = { tls = { auto = { method = "cronJob" } } }
  }

  cilium_patches_controlplane = var.cni.name == "cilium" ? [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeProxyConfig"
      enabled    = false
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeInlineManifestConfig"
      name       = "cilium"
      manifest   = data.helm_template.cilium[0].manifest
    }),
  ] : []
}

data "helm_template" "cilium" {
  count = var.cni.name == "cilium" ? 1 : 0

  name         = "cilium"
  namespace    = "kube-system"
  chart        = "${path.module}/deps/vendor/cilium"
  kube_version = var.kubernetes_version
  values       = concat([yamlencode(local.cilium_base_values)], var.cni.configuration)

  lifecycle {
    precondition {
      condition     = var.kubernetes_version != null
      error_message = "cni.name = \"cilium\" requires kubernetes_version to be set."
    }
  }
}
