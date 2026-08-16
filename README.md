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


## Security

The module's state is highly sensitive: it stores the generated Talos machine
secrets and the cluster `kubeconfig` in plaintext. Treat state like a credential:

- **Use an encrypted remote backend for production.** Prefer Terraform/OpenTofu
  cloud backends or an S3/GCS/Azure backend with server-side encryption (KMS)
  enabled, and enable state locking. Avoid the default local backend with state
  on shared or untracked disk.
- **Restrict state access.** Only operators who need cluster administration
  rights should be able to read state, backups, or the outputs.
- **Protect operator credentials.** Lock down the OpenTofu CLI configuration
  and any cloud/provider credentials on machines running `tofu apply`. Never
  commit `*.tfvars` (local overrides are already gitignored).
- **Sensitive outputs.** All module outputs (`talosconfig`, machine secrets,
  `kubeconfig`) are `sensitive = true` and are not printed in plans or console
  output; avoid piping them into logs or files outside the state/backend.
