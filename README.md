# Talos

This repository contains a Terraform / OpenTofu module to deploy a Kubernetes
cluster on bare-metal servers using [Talos](https://www.talos.dev/). Nodes are
declared in groups (by hardware or purpose class); the module generates machine
secrets, applies each node's configuration, bootstraps the cluster and emits a
`talosconfig` and `kubeconfig`.

## Requirements

- Server(s) with booted Talos in maintenance mode
- Talos >= 1.14 on the nodes
- `siderolabs/talos` provider >= 0.12.0

Upgrading from v0.3.0? See [Upgrading to v1](docs/upgrading-to-v1.md).

## Usage

```hcl
module "talos" {
  source = "path/to/talos"

  cluster_name = "my-cluster"

  node_groups = {
    cp = {
      role  = "controlplane"
      image = { version = "v1.14.5" }
      nodes = {
        c1 = { ip_address = "192.168.1.1" }
      }
    }
    workers = {
      role               = "worker"
      image              = { version = "v1.14.5", extensions = ["siderolabs/iscsi-tools"] }
      install_disk_match = "disk.dev_path == \"/dev/vda\""
      labels             = { "example.com/pool" = "storage" }
      config_patches = [
        yamlencode({
          apiVersion = "v1alpha1"
          kind       = "TimeSyncConfig"
          ntp        = { servers = ["time.cloudflare.com"] }
        })
      ]
      nodes = {
        w1 = { ip_address = "192.168.1.2" }
      }
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.12.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
| [talos_image_factory_schematic.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/image_factory_schematic) | resource |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/client_configuration) | data source |
| [talos_cluster_health.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/cluster_health) | data source |
| [talos_image_factory_extensions_versions.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/image_factory_extensions_versions) | data source |
| [talos_image_factory_urls.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/image_factory_urls) | data source |
| [talos_machine_configuration.controlplane](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | A name to provide for the Talos cluster | `string` | n/a | yes |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Node groups by hardware or purpose class. Each group carries a role,<br/>an image spec, and shared settings. Nodes inherit and can override. | <pre>map(object({<br/>    role = string<br/>    image = object({<br/>      version           = optional(string)<br/>      extensions        = optional(list(string), [])<br/>      extra_kernel_args = optional(list(string), [])<br/>      architecture      = optional(string, "amd64")<br/>      platform          = optional(string, "metal")<br/>      secureboot        = optional(bool, false)<br/>      installer         = optional(string)<br/>    })<br/>    install_disk_match = optional(string)<br/>    labels             = optional(map(string), {})<br/>    annotations        = optional(map(string), {})<br/>    taints             = optional(map(string), {})<br/>    config_patches     = optional(list(string), [])<br/>    nodes = map(object({<br/>      ip_address         = string<br/>      install_disk_match = optional(string)<br/>      labels             = optional(map(string), {})<br/>      annotations        = optional(map(string), {})<br/>      taints             = optional(map(string), {})<br/>      config_patches     = optional(list(string), [])<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_allow_scheduling_on_controlplanes"></a> [allow\_scheduling\_on\_controlplanes](#input\_allow\_scheduling\_on\_controlplanes) | Remove the default NoSchedule taint from control plane nodes,<br/>allowing regular workloads to be scheduled on them. | `bool` | `false` | no |
| <a name="input_apply_mode"></a> [apply\_mode](#input\_apply\_mode) | The apply mode for talos\_machine\_configuration\_apply.<br/>Use "staged\_if\_needing\_reboot" for safe migrations. | `string` | `"auto"` | no |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | The URL of the Talos cluster API server, e.g. https://10.0.0.1:6443.<br/>Derived from controlplane\_address when unset. | `string` | `null` | no |
| <a name="input_config_patches"></a> [config\_patches](#input\_config\_patches) | YAML config patches applied to all nodes. | `list(string)` | `[]` | no |
| <a name="input_controlplane_address"></a> [controlplane\_address](#input\_controlplane\_address) | Address of the controlplane without scheme or port; may be a load balancer host.<br/>Defaults to the first controlplane node IP. | `string` | `null` | no |
| <a name="input_enable_cluster_health_check"></a> [enable\_cluster\_health\_check](#input\_enable\_cluster\_health\_check) | Whether to wait for the cluster to report healthy (etcd quorum, all<br/>nodes Ready, control plane static pods running, etc.) before creating<br/>the kubeconfig. Defaults to true.<br/><br/>Disabling this is occasionally necessary when the health check's<br/>assumptions don't hold for a given network topology: it requires the<br/>Kubernetes Node object to report an address matching the corresponding<br/>`node_groups.*.nodes.*.ip_address`, which fails if the KubeNodeConfig<br/>nodeIP is patched (via config\_patches) to prefer a different subnet than<br/>the one `node_groups.*.nodes.*.ip_address` uses - e.g. when node\_groups<br/>uses each node's public IP (so Terraform/talosctl stay reachable from<br/>outside the cluster) but the KubeNodeConfig nodeIP is pinned to a private<br/>network for internal traffic. | `bool` | `true` | no |
| <a name="input_kubelet_server_tls_bootstrap"></a> [kubelet\_server\_tls\_bootstrap](#input\_kubelet\_server\_tls\_bootstrap) | Enable kubelet server TLS bootstrapping on all nodes.<br/>Requires a CSR approver (e.g. kubelet-serving-cert-approver). | `bool` | `false` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The version of Kubernetes to use, e.g. `1.30.0` or `v1.32.0` | `string` | `null` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The Talos version contract used to generate secrets and machine configuration,<br/>e.g. `v1.14` or `1.14.5`. Must be v1.14 or newer. Optional: the provider<br/>computes a default when unset.<br/>This does not control the installed Talos version - set it via<br/>node\_groups.*.image. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_installer_images"></a> [installer\_images](#output\_installer\_images) | The resolved installer image reference for each node group. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | n/a |
| <a name="output_kubernetes_client_configuration"></a> [kubernetes\_client\_configuration](#output\_kubernetes\_client\_configuration) | n/a |
| <a name="output_talos_machine_secrets"></a> [talos\_machine\_secrets](#output\_talos\_machine\_secrets) | n/a |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | n/a |
<!-- END_TF_DOCS -->

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
- **Sensitive outputs.** The `talosconfig`, machine secrets and `kubeconfig`
  outputs are `sensitive = true` and are not printed in plans or console
  output; avoid piping them into logs or files outside the state/backend.

## Documentation

- [Node groups](docs/node-groups.md): groups, nodes and merge rules
- [Images](docs/images.md): Image Factory specs, raw installers, upgrades
- [Disk selection](docs/disk-selection.md): `install_disk_match` CEL expressions
- [Config patches](docs/config-patches.md): patch order, documents, legacy field migration
- [Kubernetes nodes](docs/kubernetes-nodes.md): labels, annotations, taints, kubelet TLS
- [Upgrading to v1](docs/upgrading-to-v1.md): v0.3.0 to 1.0.0 migration
- [Renewing an expired talosconfig](docs/talosconfig-renewal.md)
