# Images

Each group's `image` is either a **Factory spec** or a **raw installer**. Setting
both, or neither, fails validation.

## Factory spec

```hcl
image = {
  version           = "v1.14.5"
  extensions        = ["siderolabs/iscsi-tools"]
  extra_kernel_args = ["console=ttyS0"]
  architecture      = "amd64" # default
  platform          = "metal" # default
  secureboot        = false   # default
}
```

The module resolves it through the [Image Factory](https://factory.talos.dev/):

1. If `extensions` is set, each name is looked up for `version`. If any name
   doesn't exist for that Talos version, `plan` fails with the group name.
2. A schematic is created with the extensions and `extra_kernel_args`. One
   schematic per Factory group.
3. The installer URL is taken from the schematic: `installer_secureboot` if
   `secureboot = true`, otherwise `installer`.
4. That URL goes into `UnattendedInstallConfig.installer.image` on every node of
   the group.

`version` should match the Talos version your nodes will run. The module only
requires it to be at least `talos_version` when that is set.

## Raw installer

```hcl
image = { installer = "registry.example.com/siderolabs/installer:v1.14.5" }
```

The reference is used as is. No Image Factory calls are made, so `architecture`,
`platform` and `secureboot` (and `extensions`, `extra_kernel_args`) are ignored:
they only apply to Factory lookups.

## Resolved images

The `installer_images` output maps each group to its resolved installer
reference:

```hcl
installer_images = {
  cp      = "factory.talos.dev/metal-installer/<schematic-id>:v1.14.5"
  workers = "factory.talos.dev/metal-installer/<schematic-id>:v1.14.5"
}
```

## Changing an image does not upgrade nodes

The installer image is only used when Talos is installed to disk. Changing
`image` (a new version, extension or kernel argument) updates the machine
configuration but does **not** upgrade running nodes. Upgrade them with
`talosctl`, using the reference from the output:

```bash
talosctl -n <node-ip> upgrade --image "$(tofu output -json installer_images | jq -r .workers)"
```

Use `apply_mode = "staged_if_needing_reboot"` to avoid reboots while applying
configuration changes.

## Validation

The module checks that `image` is exactly one of the two forms, that the version
looks like a version, and that extensions exist. It does not validate the
installer image itself or `install_disk_match`: `talosctl validate --mode metal`
catches problems in the generated machine configuration, including CEL errors
(see [Disk selection](disk-selection.md)).
