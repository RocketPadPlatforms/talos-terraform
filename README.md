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
      "my-cluster-c1" = {
        ip_address   = "192.168.1.1"
        install_disk = "/dev/sda"
        hostname     = "my-cluster-c1"
      }
    }
    workers = {
      "my-cluster-w1" = {
        ip_address   = "192.168.1.2"
        install_disk = "/dev/sda"
      }
    }
  }
  config_patches_controlplane = [
    "path/to/my-patch-cp-a.yaml",
    "path/to/my-patch-cp-b.yaml"
  ]
  config_patches_worker = [
    "path/to/my-patch-worker-a.yaml",
    "path/to/my-patch-worker-b.yaml"
  ]
  config_patches_all = [
    "path/to/my-patch-all-a.yaml",
    "path/to/my-patch-all-b.yaml"
  ]
}
```
