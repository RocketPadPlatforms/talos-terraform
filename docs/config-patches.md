# Config patches

Patches are YAML strings (use `yamlencode(...)` or `file(...)`) merged into each
node's machine configuration by the provider.

## Order

For each node, patches apply from general to specific. Later patches win.

1. **Module patches**
   1. `machine.certSANs` (Talos API certificate)
   2. `UnattendedInstallConfig`: the group's installer image, plus the disk match if set
   3. `KubeNodeConfig` taint delete (controlplanes, when `allow_scheduling_on_controlplanes` is true)
   4. `KubeNodeConfig` with the merged labels, annotations and taints (only if any are set)
   5. `KubeletConfig` with `serverTLSBootstrap` (when `kubelet_server_tls_bootstrap` is true, or the `kubelet_cert_approver` or `metrics_server` addon is enabled)
   6. `UserVolumeConfig` `local-path-provisioner` (when the `local_path_provisioner` addon is enabled)
   7. Controlplanes only: the [Cilium](cilium.md) documents (`KubeFlannelCNIConfig` delete, `KubeProxyConfig` disabled, `KubeInlineManifestConfig` `cilium`), then one `KubeInlineManifestConfig` per enabled [addon](addons.md)
   8. `VolumeConfig` `STATE` and `EPHEMERAL` (when the group sets [`disk_encryption`](security.md#disk-encryption))
   9. `HostnameConfig` with the node's `hostname` and `auto` deleted (when the node sets [`hostname`](#hostnames))
2. `config_patches` (cluster-wide)
3. the group's `config_patches`
4. the node's `config_patches`

## Multi-document patches

Talos 1.14 splits configuration into documents. A patch string may hold several
documents separated by `---`:

```hcl
config_patches = [
  <<-EOT
    apiVersion: v1alpha1
    kind: ResolverConfig
    nameservers:
      - address: 1.1.1.1
    ---
    apiVersion: v1alpha1
    kind: TimeSyncConfig
    ntp:
      servers:
        - time.cloudflare.com
  EOT
]
```

Only the format above is supported. JSON6902 patches are not.

## Legacy fields to documents

The module emits only the new documents (`machine.certSANs` is the exception: it
has no replacement and stays in `v1alpha1`). Legacy `v1alpha1` fields in your
patches may be rejected or ignored by Talos 1.14. Move them as follows (see the
[v1.14 document map](https://docs.siderolabs.com/talos/v1.14/reference/configuration/document-map)):

| Legacy field | Document |
|---|---|
| `machine.network` | `HostnameConfig`, `KubeSpanConfig`, `LinkConfig`, `ResolverConfig`, `StaticHostConfig` |
| `machine.network.nameservers` | `ResolverConfig` |
| `machine.time` | `TimeSyncConfig` |
| `machine.kubelet` | `KubeletConfig` |
| `machine.kubelet.nodeIP`, `registerWithFQDN`, `skipNodeRegistration` | `KubeNodeConfig` |
| `machine.nodeLabels`, `nodeAnnotations`, `nodeTaints` | `KubeNodeConfig` |
| `machine.install` | Module inputs: `node_groups.*.image` and `install_disk_match` |
| `machine.certSANs` | Still `v1alpha1`: no replacement document |
| `cluster.allowSchedulingOnControlPlanes`, `cluster.allowSchedulingOnMasters` | Module input `allow_scheduling_on_controlplanes` (a `KubeNodeConfig` taint delete) |
| `cluster.network.cni` | `KubeFlannelCNIConfig`, `KubeNetworkConfig` |
| `cluster.extraManifests` | `KubeExternalManifestConfig` |
| `cluster.inlineManifests` | `KubeInlineManifestConfig` |
| `cluster.aescbcEncryptionSecret`, `secretboxEncryptionSecret` | `KubeEtcdEncryptionConfig` |
| `cluster.apiServer` | `KubeAPIServerConfig` |
| `cluster.controllerManager` | `KubeControllerManagerConfig` |
| `cluster.scheduler` | `KubeSchedulerConfig` |
| `cluster.proxy` | `KubeProxyConfig` |
| `cluster.coreDNS` | `KubeCoreDNSConfig` |
| `machine.registries` | `RegistryAuthConfig`, `RegistryMirrorConfig`, `RegistryTLSConfig` |
| `machine.sysctls` | `SysctlConfig` |
| `machine.sysfs` | `SysfsConfig` |
| `machine.kernel` | `KernelModuleConfig` |
| `machine.env` | `EnvironmentConfig` |
| `machine.files` | `CRICustomizationConfig`, `EtcFileConfig` |
| `machine.disks` | `UserVolumeConfig` |
| `machine.systemDiskEncryption` | `VolumeConfig` |
| `machine.udev` | `UdevRulesConfig` |

## Deleting fields with `$patch: delete`

Strategic merge patches remove a field with `$patch: delete`. For `KubeNodeConfig`
taints, only this exact form works:

```yaml
apiVersion: v1alpha1
kind: KubeNodeConfig
taints:
  $patch: delete
```

`taints: null` and `taints: {}` are accepted but silently do nothing, so the
taint stays. The module uses the working form for
`allow_scheduling_on_controlplanes`. Because that patch runs before the module's
labels/annotations/taints patch, it removes only the generated controlplane
taint. To clear taints yourself, add a `$patch: delete` patch in
`config_patches`: it runs after the module's taints, so it removes those too.

## Hostnames

The base configuration sets `HostnameConfig` `auto: stable`, and Talos rejects a
`HostnameConfig` with both `auto` and `hostname`. The module's patch for
`node_groups.*.nodes.*.hostname` deletes `auto`. In your own patches:

- On a node with `hostname`, another `hostname` replaces the module's value:

  ```yaml
  apiVersion: v1alpha1
  kind: HostnameConfig
  hostname: other-name
  ```

- On a node with `hostname`, going back to a generated hostname deletes the
  module's value:

  ```yaml
  apiVersion: v1alpha1
  kind: HostnameConfig
  hostname:
    $patch: delete
  auto: stable
  ```

- On a node without `hostname`, setting one in a patch must delete `auto`:

  ```yaml
  apiVersion: v1alpha1
  kind: HostnameConfig
  auto:
    $patch: delete
  hostname: node-a
  ```

## Known issues

- **Provider 0.12.0 drops explicitly empty lists in document patches**, e.g.
  `domains: []` in `ResolverConfig`. The field is left at its previous value.
  Omit the field or set a non-empty value.
