# Disk selection

`install_disk_match` is a [CEL](https://github.com/google/cel-spec) expression
that picks the install disk. It is set on a group or on a single node (the node's
value replaces the group's) and ends up in
`UnattendedInstallConfig.provisioning.diskSelector.match`.

When `install_disk_match` is not set, the module does not emit a disk selector.
The Talos generator's default (`disk.dev_path == "/dev/sda"`) applies. Set a
match for any other layout.

## Examples

| Goal | Expression |
|---|---|
| A specific device | `disk.dev_path == "/dev/vda"` |
| A by-id symlink | `"/dev/disk/by-id/wwn-0x5000" in disk.symlinks` |
| NVMe larger than 100 GB | `disk.transport == "nvme" && disk.size > 100u * GB` |

In HCL, escape the quotes or use a heredoc:

```hcl
install_disk_match = "disk.dev_path == \"/dev/vda\""
install_disk_match = "disk.transport == \"nvme\" && disk.size > 100u * GB"
```

## The `100u` pitfall

`disk.size` is unsigned. CEL doesn't mix types, so `100 * GB` (int times uint)
fails. Write `100u * GB`.

## Validation

The module passes the string through without checking it. A CEL error shows up
when Talos validates or applies the configuration. Catch it earlier by
validating a rendered machine configuration:

```bash
talosctl validate --mode metal --config controlplane.yaml
```
