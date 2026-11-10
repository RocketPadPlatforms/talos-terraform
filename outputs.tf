output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "talos_machine_secrets" {
  value     = resource.talos_machine_secrets.this.machine_secrets
  sensitive = true
}

output "kubeconfig" {
  value     = resource.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "kubernetes_client_configuration" {
  value     = resource.talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive = true
}

output "manifests_sync_command" {
  description = <<-EOT
    talosctl command that re-applies the module's bootstrap manifests (Cilium,
    addons) and prunes removed ones, without changing the Kubernetes version.
    Run it with --dry-run first. Null when kubernetes_version is unset.
  EOT
  value       = var.kubernetes_version == null ? null : "talosctl -n ${local.bootstrap_node} upgrade-k8s --to ${var.kubernetes_version}"
  sensitive   = false
}

output "installer_images" {
  description = "The resolved installer image reference for each node group."
  value       = { for group, _ in var.node_groups : group => local.group_images[group] }
  sensitive   = false
}
