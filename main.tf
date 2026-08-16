locals {
  // List of ip addresses of all control plane nodes
  // `for_each` iterates maps in lexicographic-key order, so indexed access is
  // deterministic. Non-empty is enforced by a validation on `var.node_data`.
  controlplane_ip_addresses = [for each in var.node_data.controlplanes : each.ip_address]

  // Address of the controlplane
  // Used as the cluster endpoint; first controlplane IP is the fallback
  // when no load balancer address is set.
  controlplane_address = var.controlplane_address != null ? var.controlplane_address : local.controlplane_ip_addresses[0]

  // Bootstrap and kubeconfig always target a real control plane node: a load
  // balancer/VIP has no healthy backends before the cluster is bootstrapped.
  bootstrap_node = local.controlplane_ip_addresses[0]

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

resource "talos_machine_configuration_apply" "this" {
  for_each = merge(
    { for name, node in var.node_data.controlplanes : "controlplane-${name}" => { role = "controlplane", node = node } },
    { for name, node in var.node_data.workers : "worker-${name}" => { role = "worker", node = node } }
  )

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    each.value.role == "controlplane"
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )
  node = each.value.node.ip_address
  config_patches = concat(
    [
      yamlencode({
        machine = {
          // The cluster endpoint (load balancer/VIP or first controlplane) must
          // be a SAN of every API server certificate for workers and clients to
          // trust it over TLS. distinct() de-duplicates the single-node case.
          certSANs = (
            each.value.role == "controlplane"
            ? distinct([each.value.node.ip_address, local.controlplane_address])
            : [each.value.node.ip_address]
          )
          install = {
            disk         = each.value.node.install_disk
            diskSelector = each.value.node.install_disk_selector
          }
        }
      })
    ],
    // Set install image only if its configured
    each.value.node.install_image != null ? [
      yamlencode({
        machine = {
          install = {
            image = each.value.node.install_image
          }
        }
      })
    ] : [],
    each.value.role == "controlplane" ? var.config_patches_controlplane : var.config_patches_worker,
    var.config_patches_all,
    each.value.node.talos_patches != null ? each.value.node.talos_patches : []
  )
  on_destroy = {
    reset    = true
    reboot   = true
    graceful = false
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node
}

data "talos_cluster_health" "this" {
  depends_on = [talos_machine_configuration_apply.this, talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ip_addresses
  control_plane_nodes  = local.controlplane_ip_addresses
  worker_nodes         = [for each in var.node_data.workers : each.ip_address]

  timeouts = {
    read = "15m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node
}

# For the migration of the Talos provider to version 0.6.0
moved {
  from = data.talos_cluster_kubeconfig.this
  to   = talos_cluster_kubeconfig.this
}
