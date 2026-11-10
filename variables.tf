variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = <<-EOT
    The URL of the Talos cluster API server, e.g. https://10.0.0.1:6443.
    Derived from controlplane_address when unset.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.cluster_endpoint == null || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https:// URL, e.g. https://10.0.0.1:6443."
  }
}

variable "controlplane_address" {
  description = <<-EOT
    Address of the controlplane without scheme or port; may be a load balancer host.
    Defaults to the first controlplane node IP.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.controlplane_address == null || !can(regex("(://|:[0-9]+$)", var.controlplane_address))
    error_message = "controlplane_address must be a bare host/IP without scheme or port, e.g. 10.0.0.1."
  }
}

variable "kubernetes_version" {
  description = "The version of Kubernetes to use, e.g. `1.30.0` or `v1.32.0`"
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^v?\\d+\\.\\d+", var.kubernetes_version))
    error_message = "kubernetes_version must look like a version, e.g. 1.30.0 or v1.32.0."
  }
}

variable "talos_version" {
  description = <<-EOT
    The Talos version contract used to generate secrets and machine configuration,
    e.g. `v1.14` or `1.14.5`. Must be v1.14 or newer. Optional: the provider
    computes a default when unset.
    This does not control the installed Talos version - set it via
    node_groups.*.image.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.talos_version == null || can(regex("^v?\\d+\\.\\d+", var.talos_version))
    error_message = "talos_version must look like a version, e.g. v1.14 or 1.14.5."
  }

  validation {
    condition = var.talos_version == null || try(
      tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[0]) > 1 ||
      (
        tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[0]) == 1 &&
        tonumber(regex("^v?(\\d+)\\.(\\d+)", var.talos_version)[1]) >= 14
      ),
      true
    )
    error_message = "talos_version must be v1.14 or newer."
  }
}

variable "config_patches" {
  description = "YAML config patches applied to all nodes."
  type        = list(string)
  default     = []
}

variable "allow_scheduling_on_controlplanes" {
  description = <<-EOT
    Remove the default NoSchedule taint from control plane nodes,
    allowing regular workloads to be scheduled on them.
  EOT
  type        = bool
  default     = false
}

variable "kubelet_server_tls_bootstrap" {
  description = <<-EOT
    Enable kubelet server TLS bootstrapping on all nodes.
    Requires a CSR approver (e.g. kubelet-serving-cert-approver).
    Enabled automatically by addons.kubelet_cert_approver and
    addons.metrics_server.
  EOT
  type        = bool
  default     = false
}

variable "apply_mode" {
  description = <<-EOT
    The apply mode for talos_machine_configuration_apply.
    Use "staged_if_needing_reboot" for safe migrations.
  EOT
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "staged", "staged_if_needing_reboot", "no_reboot", "reboot"], var.apply_mode)
    error_message = "apply_mode must be one of: auto, staged, staged_if_needing_reboot, no_reboot, reboot."
  }
}

variable "node_groups" {
  description = <<-EOT
    Node groups by hardware or purpose class. Each group carries a role,
    an image spec, and shared settings. Nodes inherit and can override.
    Never add, remove or change disk_encryption on a group with provisioned
    nodes: they fail to boot on the next reboot (see docs/security.md).
  EOT
  type = map(object({
    role = string
    image = object({
      version           = optional(string)
      extensions        = optional(list(string), [])
      extra_kernel_args = optional(list(string), [])
      architecture      = optional(string, "amd64")
      platform          = optional(string, "metal")
      secureboot        = optional(bool, false)
      installer         = optional(string)
    })
    install_disk_match = optional(string)
    disk_encryption = optional(object({
      method       = string
      kms_endpoint = optional(string)
    }))
    labels         = optional(map(string), {})
    annotations    = optional(map(string), {})
    taints         = optional(map(string), {})
    config_patches = optional(list(string), [])
    nodes = map(object({
      ip_address         = string
      install_disk_match = optional(string)
      labels             = optional(map(string), {})
      annotations        = optional(map(string), {})
      taints             = optional(map(string), {})
      config_patches     = optional(list(string), [])
    }))
  }))

  validation {
    condition = length(flatten([
      for g in values(var.node_groups) : [
        for n in keys(g.nodes) : n if g.role == "controlplane"
      ]
    ])) > 0
    error_message = "At least one controlplane node must be provided."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) : contains(["controlplane", "worker"], g.role)
    ])
    error_message = "Each node group role must be 'controlplane' or 'worker'."
  }

  validation {
    condition = alltrue(flatten([
      for g in values(var.node_groups) : [
        for n in values(g.nodes) :
        length(n.ip_address) > 0 && !can(regex("\\s", n.ip_address))
      ]
    ]))
    error_message = "Every node ip_address must be non-empty without whitespace."
  }

  validation {
    condition = length(flatten([
      for g in values(var.node_groups) : keys(g.nodes)
      ])) == length(distinct(flatten([
        for g in values(var.node_groups) : keys(g.nodes)
    ])))
    error_message = "Node names must be unique across all groups."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) :
      (g.image.installer != null) != (g.image.version != null)
    ])
    error_message = "Each image must set either 'installer' (raw ref) or 'version' (Factory spec), not both."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) :
      g.image.version == null || can(regex("^v?\\d+\\.\\d+", g.image.version))
    ])
    error_message = "image.version must look like a version, e.g. v1.14.5."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) :
      g.image.version == null || try(
        tonumber(regex("^v?(\\d+)\\.(\\d+)", g.image.version)[0]) > 1 ||
        (
          tonumber(regex("^v?(\\d+)\\.(\\d+)", g.image.version)[0]) == 1 &&
          tonumber(regex("^v?(\\d+)\\.(\\d+)", g.image.version)[1]) >= 14
        ),
        true
      )
    ])
    error_message = "image.version must be v1.14 or newer."
  }

  validation {
    condition = alltrue(flatten([
      for g in values(var.node_groups) : concat(
        [for v in values(g.taints) : can(regex("^([^:]*:)?(NoSchedule|PreferNoSchedule|NoExecute)$", v))],
        flatten([for n in values(g.nodes) : [
          for v in values(n.taints) : can(regex("^([^:]*:)?(NoSchedule|PreferNoSchedule|NoExecute)$", v))
        ]])
      )
    ]))
    error_message = "Taint values must match '[<value>:]NoSchedule|PreferNoSchedule|NoExecute'."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) :
      g.disk_encryption == null || contains(["tpm", "nodeID", "kms"], try(g.disk_encryption.method, ""))
    ])
    error_message = "disk_encryption.method must be 'tpm', 'nodeID' or 'kms'."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) : try(
        g.disk_encryption.method == "kms"
        ? can(regex("^https://", g.disk_encryption.kms_endpoint))
        : g.disk_encryption.kms_endpoint == null,
        true
      )
    ])
    error_message = "disk_encryption.kms_endpoint is required for method 'kms', only allowed there, and must be an https:// URL."
  }

  validation {
    condition = alltrue([
      for g in values(var.node_groups) :
      try(g.disk_encryption.method, "") != "tpm" || g.image.version == null || g.image.secureboot
    ])
    error_message = "disk_encryption.method 'tpm' requires image.secureboot = true on Image Factory groups."
  }
}

variable "enable_cluster_health_check" {
  description = <<-EOT
    Whether to wait for the cluster to report healthy (etcd quorum, all
    nodes Ready, control plane static pods running, etc.) before creating
    the kubeconfig. Defaults to true.

    Disabling this is occasionally necessary when the health check's
    assumptions don't hold for a given network topology: it requires the
    Kubernetes Node object to report an address matching the corresponding
    `node_groups.*.nodes.*.ip_address`, which fails if the KubeNodeConfig
    nodeIP is patched (via config_patches) to prefer a different subnet than
    the one `node_groups.*.nodes.*.ip_address` uses - e.g. when node_groups
    uses each node's public IP (so Terraform/talosctl stay reachable from
    outside the cluster) but the KubeNodeConfig nodeIP is pinned to a private
    network for internal traffic.
  EOT
  type        = bool
  default     = true
}
