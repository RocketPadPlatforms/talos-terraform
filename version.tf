terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0"
    }
  }
}
