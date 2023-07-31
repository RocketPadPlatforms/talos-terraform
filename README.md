# Talos

This repository contains a Terraform module to deploy a Kubernetes cluster using
[Talos](https://www.talos.dev/).


## Requirements

- Server(s) with booted Talos in maintenance mode


## Usage

```
module "talos" {
  source  = "path/to/talos"

  cluster_name = "my-cluster"
  cluster_endpoint = "https://192.168.1.1:6443"
  node_data = {
    controlplanes = {
      "192.168.1.1" = {
        install_disk = "/dev/sda"
        hostname     = "my-cluster-c1"
      }
    }
    workers = {
      "192.168.1.2" = {
        install_disk = "/dev/sda"
        hostname     = "my-cluster-w1"
      }
    }
  }
  config_patches = [
    "path/to/my-patch-a.yaml",
    "path/to/my-patch-b.yaml"
  ]
}
```
