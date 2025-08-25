locals {
  // List of ip addresses of all control plane nodes
  controlplane_ip_addresses = [for each in var.node_data.controlplanes : each.ip_address]

  // Address of the controlplane
  controlplane_address = var.controlplane_address != null ? var.controlplane_address : local.controlplane_ip_addresses[0]

  // Talos cluster endpoint
  // If `var.cluster_endpoint` is not set it will build the endpoint based on the ip address of the first control plane node
  cluster_endpoint = var.cluster_endpoint != null ? var.cluster_endpoint : format("https://%s:6443", local.controlplane_address)
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  docs               = false
  examples           = false
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
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
  endpoints            = local.controlplane_ip_addresses
  nodes                = local.controlplane_ip_addresses
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
            disk         = try(each.value.install_disk, null)
            diskSelector = try(each.value.install_disk_selector, null)
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
    var.config_patches_all,
    each.value.talos_patches != null ? each.value.talos_patches : []
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
            disk         = try(each.value.install_disk, null)
            diskSelector = try(each.value.install_disk_selector, null)
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
    var.config_patches_all,
    each.value.talos_patches != null ? each.value.talos_patches : []
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
  node                 = local.controlplane_address
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [talos_machine_bootstrap.this]

  create_duration  = "30s"
  destroy_duration = "0s"
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [time_sleep.wait_30_seconds]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.controlplane_address
}

# For the migration of the Talos provider to version 0.6.0
moved {
  from = data.talos_cluster_kubeconfig.this
  to   = talos_cluster_kubeconfig.this
}
