# Node groups

Nodes are declared in `node_groups`: a map of groups by hardware or purpose
class. A group has a `role`, an `image`, shared settings, and a map of `nodes`.
Settings follow a general-to-specific hierarchy: cluster, then group, then node.

## Type

```hcl
node_groups = map(object({
  role = string # "controlplane" or "worker"
  image = object({
    version           = optional(string)
    extensions        = optional(list(string), [])
    extra_kernel_args = optional(list(string), [])
    architecture      = optional(string, "amd64")
    platform          = optional(string, "metal")
    secureboot        = optional(bool, false)
    installer         = optional(string)
  })
  install_disk_match = optional(string)
  disk_encryption = optional(object({
    method       = string           # "tpm", "nodeID" or "kms"
    kms_endpoint = optional(string) # required for "kms"
  }))
  labels         = optional(map(string), {})
  annotations    = optional(map(string), {})
  taints         = optional(map(string), {})
  config_patches = optional(list(string), [])
  nodes = map(object({
    ip_address         = string
    hostname           = optional(string)
    install_disk_match = optional(string)
    labels             = optional(map(string), {})
    annotations        = optional(map(string), {})
    taints             = optional(map(string), {})
    config_patches     = optional(list(string), [])
  }))
}))
```

See [Images](images.md) for `image`, [Disk selection](disk-selection.md) for
`install_disk_match`, [Security](security.md#disk-encryption) for
`disk_encryption`, [Config patches](config-patches.md) for `config_patches`
and [Kubernetes nodes](kubernetes-nodes.md) for labels, annotations, taints and
`hostname`.

## Merge rules

| Setting | Group + node |
|---|---|
| `labels`, `annotations`, `taints` | Merged by key; the node wins on conflict |
| `config_patches` | Appended: cluster, then group, then node |
| `install_disk_match` | The node's value replaces the group's |
| `hostname` | Node only |
| `image`, `disk_encryption` | Group only |

## Example

```hcl
node_groups = {
  cp = {
    role  = "controlplane"
    image = { version = "v1.14.5" }
    nodes = {
      c1 = { ip_address = "10.0.0.1" }
      c2 = { ip_address = "10.0.0.2" }
      c3 = { ip_address = "10.0.0.3" }
    }
  }
  general = {
    role               = "worker"
    image              = { version = "v1.14.5" }
    install_disk_match = "disk.dev_path == \"/dev/sda\""
    nodes = {
      w1 = { ip_address = "10.0.1.1" }
      w2 = { ip_address = "10.0.1.2", install_disk_match = "disk.dev_path == \"/dev/vda\"" }
    }
  }
  gpu = {
    role   = "worker"
    image  = { version = "v1.14.5", extensions = ["siderolabs/nvidia-open-gpu-kernel-modules-production"] }
    labels = { "example.com/pool" = "gpu" }
    taints = { gpu = "true:NoSchedule" }
    nodes = {
      g1 = { ip_address = "10.0.2.1" }
      g2 = { ip_address = "10.0.2.2", labels = { "example.com/pool" = "gpu-large" } }
    }
  }
}
```

## Things to know

- **Node names are unique across groups.** A name can't appear in two groups.
- **Internal keys are `<role>-<name>`.** The module's `talos_machine_configuration_apply`
  resources are keyed this way. Renaming a node, or moving it to a group with a
  different role, changes the key: the old node is reset and a new one applied.
  Moving a node between groups of the same role keeps the key.
- **The first controlplane** is the controlplane node whose name comes first
  lexicographically. It is used for the endpoint fallback, bootstrap and
  kubeconfig.
- **`hostname` is optional.** Without it, Talos generates the hostname. Set
  values must be lowercase RFC 1123 names, and their first labels unique across
  groups. The node name is never used as the hostname.
- At least one controlplane node is required.
- **`disk_encryption` is fixed once nodes are provisioned.** Adding, removing
  or changing it on a group with running nodes makes them fail on their next
  reboot. Move nodes to a new group instead; see
  [Existing nodes](security.md#existing-nodes).
