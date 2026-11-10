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
  default = {}
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
  )

  addon_patches_all = []

  addon_patches_controlplane = [
    for name in ["kubelet-serving-cert-approver", "metrics-server"] : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeInlineManifestConfig"
      name       = name
      manifest   = local.addon_manifests[name]
    }) if contains(keys(local.addon_manifests), name)
  ]
}
