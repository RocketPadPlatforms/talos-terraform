resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  docs               = false
  examples           = false
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  docs               = false
  examples           = false
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for k, v in var.node_data.controlplanes : v.ip_address]
  nodes                = [for k, v in var.node_data.controlplanes : v.ip_address]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  for_each                    = var.node_data.controlplanes
  node                        = each.value.ip_address
  config_patches = concat(
    [
      yamlencode({
        machine = {
          certSANs = [each.value.ip_address]
          install = {
            disk = each.value.install_disk
          }
          network = {
            hostname = each.key
          }
        }
      })
    ],
    // Set install image only if its configured
    each.value.install_image != null ? [
      yamlencode({
        machine = {
          install = {
            image = each.value.install_image
          }
        }
      })
    ] : [],
    var.config_patches_controlplane,
    var.config_patches_all
  )
  on_destroy = {
    reset    = true
    reboot   = true
    graceful = false
  }
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  for_each                    = var.node_data.workers
  node                        = each.value.ip_address
  config_patches = concat(
    [
      yamlencode({
        machine = {
          certSANs = [each.value.ip_address]
          install = {
            disk = each.value.install_disk
          }
          network = {
            hostname = each.key
          }
        }
      })
    ],
    // Set install image only if its configured
    each.value.install_image != null ? [
      yamlencode({
        machine = {
          install = {
            image = each.value.install_image
          }
        }
      })
    ] : [],
    var.config_patches_worker,
    var.config_patches_all
  )
  on_destroy = {
    reset    = true
    reboot   = true
    graceful = false
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for k, v in var.node_data.controlplanes : v.ip_address][0]
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [talos_machine_bootstrap.this]

  create_duration  = "30s"
  destroy_duration = "0s"
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [time_sleep.wait_30_seconds]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for k, v in var.node_data.controlplanes : v.ip_address][0]
}

# For the migration of the Talos provider to version 0.6.0
moved {
  from = data.talos_cluster_kubeconfig.this
  to   = talos_cluster_kubeconfig.this
}
