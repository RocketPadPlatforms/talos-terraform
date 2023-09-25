variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "The endpoint for the Talos cluster"
  type        = string
}

variable "node_data" {
  description = "A map of node data"
  type = object({
    controlplanes = map(object({
      install_disk = string
      hostname     = optional(string)
    }))
    workers = map(object({
      install_disk = string
      hostname     = optional(string)
    }))
  })
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
