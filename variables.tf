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
    e.g. `v1.12` or `1.12.1`. Optional: the provider computes a default when unset.
    This does not control the installed Talos version - set machine.install.image
    via per-node install_image or config_patches for that.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.talos_version == null || can(regex("^v?\\d+\\.\\d+", var.talos_version))
    error_message = "talos_version must look like a version, e.g. v1.7.6."
  }
}

variable "node_data" {
  description = <<-EOT
    A map of nodes by role and name; each node has an ip_address plus optional install
    disk/image/selector and per-node talos_patches.
  EOT
  type = object({
    controlplanes = map(object({
      ip_address            = string
      install_disk          = optional(string)
      install_disk_selector = optional(map(string))
      install_image         = optional(string)
      talos_patches         = optional(list(string))
    }))
    workers = map(object({
      ip_address            = string
      install_disk          = optional(string)
      install_disk_selector = optional(map(string))
      install_image         = optional(string)
      talos_patches         = optional(list(string))
    }))
  })

  validation {
    condition     = length(var.node_data.controlplanes) > 0
    error_message = "At least one controlplane node must be provided in node_data.controlplanes."
  }

  validation {
    condition = alltrue([
      for node in concat(values(var.node_data.controlplanes), values(var.node_data.workers)) :
      length(node.ip_address) > 0 && !can(regex("\\s", node.ip_address))
    ])
    error_message = "Every node ip_address must be a non-empty address without whitespace."
  }
}

variable "config_patches_controlplane" {
  description = "A list of Talos config patches files for controlplane nodes"
  type        = list(string)
  default     = []
}

variable "config_patches_worker" {
  description = "A list of Talos config patches files for worker nodes"
  type        = list(string)
  default     = []
}

variable "config_patches_all" {
  description = "A list of Talos config patches files for all nodes"
  type        = list(string)
  default     = []
}
