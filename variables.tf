variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "The endpoint for the Talos cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "The version of Kubnernetes to use"
  type        = string
  default     = "1.30.0"
}

variable "talos_version" {
  description = "The version of Talos to use"
  type        = string
  default     = "v1.7"
}

variable "node_data" {
  description = "A map of node data"
  type = object({
    controlplanes = map(object({
      ip_address    = string
      install_disk  = string
      install_image = optional(string)
    }))
    workers = map(object({
      ip_address    = string
      install_disk  = string
      install_image = optional(string)
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
