output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "talos_machine_secrets" {
  value     = resource.talos_machine_secrets.this.machine_secrets
  sensitive = true
}

output "kubeconfig" {
  value     = data.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "kubernetes_client_configuration" {
  value     = data.talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive = true
}
