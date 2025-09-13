terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.9.0"
    }

    jsonnet = {
      source  = "alxrem/jsonnet"
      version = ">= 2.2.0"
    }
  }
}
