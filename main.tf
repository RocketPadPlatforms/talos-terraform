locals {
  all_nodes = merge([
    for group_name, group in var.node_groups : {
      for node_name, node in group.nodes : "${group.role}-${node_name}" => {
        group_name = group_name
        node_name  = node_name
        role       = group.role
        ip_address = node.ip_address
        // coalesce() errors when both are null
        install_disk_match = node.install_disk_match != null ? node.install_disk_match : group.install_disk_match
        labels             = merge(group.labels, node.labels)
        annotations        = merge(group.annotations, node.annotations)
        taints             = merge(group.taints, node.taints)
        group_patches      = group.config_patches
        node_patches       = node.config_patches
      }
    }
  ]...)

  // sort() makes the first controlplane the lexicographically first node name
  controlplane_ip_addresses = [
    for key in sort([for key, n in local.all_nodes : key if n.role == "controlplane"]) :
    local.all_nodes[key].ip_address
  ]

  controlplane_address = var.controlplane_address != null ? var.controlplane_address : local.controlplane_ip_addresses[0]

  // Bootstrap and kubeconfig always target a real control plane node: a load
  // balancer/VIP has no healthy backends before the cluster is bootstrapped.
  bootstrap_node = local.controlplane_ip_addresses[0]

  cluster_endpoint = var.cluster_endpoint != null ? var.cluster_endpoint : format("https://%s:6443", local.controlplane_address)

  factory_groups = {
    for name, g in var.node_groups : name => g.image if g.image.version != null
  }

  group_images = merge(
    { for name, g in var.node_groups : name => g.image.installer if g.image.installer != null },
    {
      for name, image in local.factory_groups : name => (
        image.secureboot
        ? data.talos_image_factory_urls.this[name].urls.installer_secureboot
        : data.talos_image_factory_urls.this[name].urls.installer
      )
    }
  )
}

data "talos_image_factory_extensions_versions" "this" {
  for_each = { for name, image in local.factory_groups : name => image if length(image.extensions) > 0 }

  talos_version = each.value.version
  exact_filters = {
    names = each.value.extensions
  }

  lifecycle {
    postcondition {
      condition     = length(self.extensions_info) == length(distinct(each.value.extensions))
      error_message = "Node group ${each.key}: not every extension in ${jsonencode(each.value.extensions)} exists for Talos ${each.value.version}."
    }
  }
}

resource "talos_image_factory_schematic" "this" {
  for_each = local.factory_groups

  schematic = yamlencode({
    customization = merge(
      length(each.value.extensions) > 0 ? {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this[each.key].extensions_info[*].name
        }
      } : {},
      length(each.value.extra_kernel_args) > 0 ? { extraKernelArgs = each.value.extra_kernel_args } : {}
    )
  })
}

data "talos_image_factory_urls" "this" {
  for_each = local.factory_groups

  talos_version = each.value.version
  schematic_id  = talos_image_factory_schematic.this[each.key].id
  platform      = each.value.platform
  architecture  = each.value.architecture

  lifecycle {
    precondition {
      condition = var.talos_version == null ? true : (
        tonumber(regex("^v?(\\d+)\\.(\\d+)", each.value.version)[0]) * 1000 + tonumber(regex("^v?(\\d+)\\.(\\d+)", each.value.version)[1])
        >= tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[0]) * 1000 + tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[1])
      )
      error_message = "Node group ${each.key}: image.version ${each.value.version} must be >= talos_version ${coalesce(var.talos_version, "-")}."
    }
  }
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
  for_each = local.all_nodes

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    each.value.role == "controlplane"
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )
  node       = each.value.ip_address
  apply_mode = var.apply_mode
  config_patches = concat(
    [
      yamlencode({
        machine = {
          // The cluster endpoint (load balancer/VIP or first controlplane) must
          // be a SAN of every API server certificate for workers and clients to
          // trust it over TLS. distinct() de-duplicates the single-node case.
          certSANs = (
            each.value.role == "controlplane"
            ? distinct([each.value.ip_address, local.controlplane_address])
            : [each.value.ip_address]
          )
        }
      }),
      yamlencode(merge(
        {
          apiVersion = "v1alpha1"
          kind       = "UnattendedInstallConfig"
          installer  = { image = local.group_images[each.value.group_name] }
        },
        each.value.install_disk_match != null ? {
          provisioning = { diskSelector = { match = each.value.install_disk_match } }
        } : {}
      )),
    ],
    // Runs before the taints patch below so it only drops the generated
    // control-plane taint, not the group/node taints.
    var.allow_scheduling_on_controlplanes && each.value.role == "controlplane" ? [
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeNodeConfig"
        taints     = { "$patch" = "delete" }
      })
    ] : [],
    length(merge(each.value.labels, each.value.annotations, each.value.taints)) > 0 ? [
      yamlencode(merge(
        { apiVersion = "v1alpha1", kind = "KubeNodeConfig" },
        length(each.value.labels) > 0 ? { labels = each.value.labels } : {},
        length(each.value.annotations) > 0 ? { annotations = each.value.annotations } : {},
        length(each.value.taints) > 0 ? { taints = each.value.taints } : {}
      ))
    ] : [],
    var.kubelet_server_tls_bootstrap || local.kubelet_cert_approver_enabled ? [
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeletConfig"
        config     = { serverTLSBootstrap = true }
      })
    ] : [],
    local.addon_patches_all,
    each.value.role == "controlplane" ? local.addon_patches_controlplane : [],
    var.config_patches,
    each.value.group_patches,
    each.value.node_patches
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
  count = var.enable_cluster_health_check ? 1 : 0

  depends_on = [talos_machine_configuration_apply.this, talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ip_addresses
  control_plane_nodes  = local.controlplane_ip_addresses
  worker_nodes         = [for key, n in local.all_nodes : n.ip_address if n.role == "worker"]

  timeouts = {
    read = "15m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  // Reference the whole (possibly zero-instance, per count above) data
  // source rather than an indexed instance: depends_on requires a static
  // list, and depending on "all instances" of a count = 0 data source is
  // trivially satisfied, so this works whether the health check is
  // enabled or not.
  depends_on = [talos_machine_configuration_apply.this, talos_machine_bootstrap.this, data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node
}
