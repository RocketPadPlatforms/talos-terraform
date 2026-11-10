# Upgrading from v0.3.0 to 1.0.0

1.0.0 is a breaking release. The module now emits only Talos 1.14 config
documents and describes nodes with `node_groups`.

## 1. Prerequisites

- **Provider:** `siderolabs/talos` >= 0.12.0. Run `tofu init -upgrade`.
- **Nodes:** Talos >= 1.14 on every node. Upgrade the nodes first with
  `talosctl upgrade`; the module doesn't do it (see [Images](images.md)).
- **`talos_version`:** must be `null` or >= v1.14. **Never lower it** on an
  existing cluster. When unset, the provider computes the default.

## 2. `node_data` to `node_groups`

Keep the node names. Internal keys are `<role>-<name>`, and a changed key resets
the node (see [Node groups](node-groups.md)).

Before:

```hcl
node_data = {
  controlplanes = {
    "my-cluster-c1" = { ip_address = "192.168.1.1", install_disk = "/dev/sda" }
  }
  workers = {
    "my-cluster-w1" = { ip_address = "192.168.1.2", install_disk = "/dev/sda" }
  }
}
```

After:

```hcl
node_groups = {
  controlplanes = {
    role  = "controlplane"
    image = { version = "v1.14.5" }
    nodes = {
      "my-cluster-c1" = { ip_address = "192.168.1.1" }
    }
  }
  workers = {
    role  = "worker"
    image = { version = "v1.14.5" }
    nodes = {
      "my-cluster-w1" = { ip_address = "192.168.1.2" }
    }
  }
}
```

The group name doesn't affect internal keys, so you can name and split groups
freely.

## 3. Per-node fields

| v0.3.0 | 1.0.0 |
|---|---|
| `install_disk = "/dev/vda"` | `install_disk_match = "disk.dev_path == \"/dev/vda\""` |
| `install_disk_selector = { type = "nvme" }` | `install_disk_match` as a [CEL](disk-selection.md) expression, `disk.transport == "nvme"` |
| `install_image` | group `image` (`{ version = ... }`, or `{ installer = "<ref>" }` for a raw reference) |
| `machine.install.extraKernelArgs` in a patch | `image.extra_kernel_args` |
| `talos_patches` | node `config_patches` |

`install_disk_match` can be set on the group or on a node; the node's value
replaces the group's.

## 4. Patches

| v0.3.0 | 1.0.0 |
|---|---|
| `config_patches_all` | `config_patches` |
| `config_patches_controlplane` / `config_patches_worker` | group `config_patches` on the controlplane / worker groups |
| per-node `talos_patches` | node `config_patches` |

Patch order changed to general-to-specific: module, then `config_patches`, then
group, then node. Before it was role, then all, then node. If two patches set the
same field, check the winner (see [Config patches](config-patches.md)).

Patches that use legacy `v1alpha1` fields (`machine.network`, `machine.kubelet`,
`machine.install`, `cluster.network.cni`, ...) need to move to the new documents.
See the [migration table](config-patches.md#legacy-fields-to-documents).
JSON6902 patches are no longer supported.

## 5. Other changes

- `cluster.allowSchedulingOnControlPlanes` in a patch: use
  `allow_scheduling_on_controlplanes = true`.
- New `kubelet_server_tls_bootstrap` for kubelet serving certificates (needs a
  CSR approver, see [Kubernetes nodes](kubernetes-nodes.md)).
- New `apply_mode`. Set `apply_mode = "staged_if_needing_reboot"` for the
  migration apply so changes that need a reboot are staged instead of rebooting
  nodes immediately.
- New output `installer_images`. Image changes don't upgrade nodes; use
  `talosctl upgrade --image` (see [Images](images.md)).

## 6. Check the plan

Run `tofu plan`. Expect changes to `talos_machine_configuration_apply` for every
node (new documents) and new Image Factory resources (schematics) for Factory
groups. There should be no replacement of `talos_machine_configuration_apply`
resources. One listed for replacement means an internal key changed: stop and fix the node name or role.
