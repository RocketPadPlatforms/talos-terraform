# talos-terraform

This repository contains a Terraform / OpenTofu module to deploy a Kubernetes
cluster on bare-metal servers using [Talos](https://www.talos.dev/). Nodes are
declared in groups (by hardware or purpose class); the module generates machine
secrets, applies each node's configuration, bootstraps the cluster and emits a
`talosconfig` and `kubeconfig`.

## Requirements

- Server(s) with booted Talos in maintenance mode
- Talos >= 1.14 on the nodes
- `siderolabs/talos` provider >= 0.12.0
- `hashicorp/helm` provider >= 3.0 (renders Cilium locally, needs no cluster access)

The module needs the `helm` provider even when Cilium is off; run `tofu init
-upgrade` after updating the module. If your root module configures its default
`helm` provider from this module's outputs (e.g. `kubernetes_client_configuration`),
planning fails with a dependency cycle. Pass the module an unconfigured provider
instead:

```hcl
provider "helm" {
  alias = "render"
}

module "talos" {
  # ...
  providers = {
    helm = helm.render
  }
}
```

Upgrading from v0.3.0? See [Upgrading to v1](docs/upgrading-to-v1.md).

## Usage

```hcl
module "talos" {
  source = "git::https://github.com/RocketPadPlatforms/talos-terraform.git?ref=v1.1.0" # x-release-please-version

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
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.3.0 |
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
| [helm_template.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/data-sources/template) | data source |
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
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Node groups by hardware or purpose class. Each group carries a role,<br/>an image spec, and shared settings. Nodes inherit and can override.<br/>Never add, remove or change disk\_encryption on a group with provisioned<br/>nodes: they fail to boot on the next reboot (see docs/security.md). | <pre>map(object({<br/>    role = string<br/>    image = object({<br/>      version           = optional(string)<br/>      extensions        = optional(list(string), [])<br/>      extra_kernel_args = optional(list(string), [])<br/>      architecture      = optional(string, "amd64")<br/>      platform          = optional(string, "metal")<br/>      secureboot        = optional(bool, false)<br/>      installer         = optional(string)<br/>    })<br/>    install_disk_match = optional(string)<br/>    disk_encryption = optional(object({<br/>      method       = string<br/>      kms_endpoint = optional(string)<br/>    }))<br/>    labels         = optional(map(string), {})<br/>    annotations    = optional(map(string), {})<br/>    taints         = optional(map(string), {})<br/>    config_patches = optional(list(string), [])<br/>    nodes = map(object({<br/>      ip_address         = string<br/>      hostname           = optional(string)<br/>      install_disk_match = optional(string)<br/>      labels             = optional(map(string), {})<br/>      annotations        = optional(map(string), {})<br/>      taints             = optional(map(string), {})<br/>      config_patches     = optional(list(string), [])<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_addons"></a> [addons](#input\_addons) | Optional cluster addons, installed as Talos inline manifests on the<br/>control planes and kept in sync with `talosctl upgrade-k8s` (see the<br/>manifests\_sync\_command output). Each addon is an object with `enabled`<br/>plus its own settings. metrics\_server also enables kubelet\_cert\_approver. | <pre>object({<br/>    kubelet_cert_approver = optional(object({<br/>      enabled = optional(bool, false)<br/>    }), {})<br/>    metrics_server = optional(object({<br/>      enabled = optional(bool, false)<br/>    }), {})<br/>    local_path_provisioner = optional(object({<br/>      enabled               = optional(bool, false)<br/>      default_storage_class = optional(bool, false)<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_allow_scheduling_on_controlplanes"></a> [allow\_scheduling\_on\_controlplanes](#input\_allow\_scheduling\_on\_controlplanes) | Remove the default NoSchedule taint from control plane nodes,<br/>allowing regular workloads to be scheduled on them. | `bool` | `false` | no |
| <a name="input_apply_mode"></a> [apply\_mode](#input\_apply\_mode) | The apply mode for talos\_machine\_configuration\_apply.<br/>Use "staged\_if\_needing\_reboot" for safe migrations. | `string` | `"auto"` | no |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | The URL of the Talos cluster API server, e.g. https://10.0.0.1:6443.<br/>Derived from controlplane\_address when unset. | `string` | `null` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | The cluster CNI. `name` is `flannel` (Talos built-in, configured via<br/>config\_patches) or `cilium` (installed from the vendored Helm chart as a<br/>Talos inline manifest, replacing Flannel and kube-proxy). For cilium,<br/>each `configuration` entry is a YAML document of Helm values applied on<br/>top of the module's base values. Do not change `name` on a running<br/>cluster. | <pre>object({<br/>    name          = optional(string, "flannel")<br/>    configuration = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_config_patches"></a> [config\_patches](#input\_config\_patches) | YAML config patches applied to all nodes. | `list(string)` | `[]` | no |
| <a name="input_controlplane_address"></a> [controlplane\_address](#input\_controlplane\_address) | Address of the controlplane without scheme or port; may be a load balancer host.<br/>Defaults to the first controlplane node IP. | `string` | `null` | no |
| <a name="input_enable_cluster_health_check"></a> [enable\_cluster\_health\_check](#input\_enable\_cluster\_health\_check) | Whether to wait for the cluster to report healthy (etcd quorum, all<br/>nodes Ready, control plane static pods running, etc.) before creating<br/>the kubeconfig. Defaults to true.<br/><br/>Disabling this is occasionally necessary when the health check's<br/>assumptions don't hold for a given network topology: it requires the<br/>Kubernetes Node object to report an address matching the corresponding<br/>`node_groups.*.nodes.*.ip_address`, which fails if the KubeNodeConfig<br/>nodeIP is patched (via config\_patches) to prefer a different subnet than<br/>the one `node_groups.*.nodes.*.ip_address` uses - e.g. when node\_groups<br/>uses each node's public IP (so Terraform/talosctl stay reachable from<br/>outside the cluster) but the KubeNodeConfig nodeIP is pinned to a private<br/>network for internal traffic. | `bool` | `true` | no |
| <a name="input_kubelet_server_tls_bootstrap"></a> [kubelet\_server\_tls\_bootstrap](#input\_kubelet\_server\_tls\_bootstrap) | Enable kubelet server TLS bootstrapping on all nodes.<br/>Requires a CSR approver (e.g. kubelet-serving-cert-approver).<br/>Enabled automatically by addons.kubelet\_cert\_approver and<br/>addons.metrics\_server. | `bool` | `false` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The version of Kubernetes to use, e.g. `1.30.0` or `v1.32.0` | `string` | `null` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | The Talos version contract used to generate secrets and machine configuration,<br/>e.g. `v1.14` or `1.14.5`. Must be v1.14 or newer. Optional: the provider<br/>computes a default when unset.<br/>This does not control the installed Talos version - set it via<br/>node\_groups.*.image. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_installer_images"></a> [installer\_images](#output\_installer\_images) | The resolved installer image reference for each node group. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Admin kubeconfig for the cluster. |
| <a name="output_kubernetes_client_configuration"></a> [kubernetes\_client\_configuration](#output\_kubernetes\_client\_configuration) | Admin client configuration for the Kubernetes API (host, CA certificate, client certificate and key). |
| <a name="output_manifests_sync_command"></a> [manifests\_sync\_command](#output\_manifests\_sync\_command) | talosctl command that re-applies the module's bootstrap manifests (Cilium,<br/>addons) and prunes removed ones, without changing the Kubernetes version.<br/>Run it with --dry-run first. Null when kubernetes\_version is unset. |
| <a name="output_talos_machine_secrets"></a> [talos\_machine\_secrets](#output\_talos\_machine\_secrets) | The cluster's machine secrets, including the Talos, Kubernetes and etcd CA keys. |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | talosconfig with an admin client certificate, targeting the control plane nodes. |
<!-- END_TF_DOCS -->

## Security

The module's state stores the Talos machine secrets and the cluster
`kubeconfig` in plaintext: use an encrypted remote backend and restrict who can
read it. See [Security](docs/security.md) for state handling, network exposure,
disk encryption (`node_groups.*.disk_encryption`), SecureBoot and more.

To report a vulnerability, follow the
[security policy](https://github.com/RocketPadPlatforms/.github/blob/main/SECURITY.md).

## Documentation

- [Node groups](docs/node-groups.md): groups, nodes and merge rules
- [Images](docs/images.md): Image Factory specs, raw installers, upgrades
- [Disk selection](docs/disk-selection.md): `install_disk_match` CEL expressions
- [Config patches](docs/config-patches.md): patch order, documents, legacy field migration
- [Kubernetes nodes](docs/kubernetes-nodes.md): labels, annotations, taints, kubelet TLS
- [Cilium](docs/cilium.md): replacing Flannel and kube-proxy with Cilium
- [Addons](docs/addons.md): cert approver, metrics-server, local-path-provisioner, lifecycle
- [Upgrading to v1](docs/upgrading-to-v1.md): v0.3.0 to 1.0.0 migration
- [Security](docs/security.md): state, network exposure, disk encryption, SecureBoot
- [Renewing an expired talosconfig](docs/talosconfig-renewal.md)
