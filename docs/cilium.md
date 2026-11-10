# Cilium

`cni.name` selects the cluster CNI. The default `flannel` is the Talos built-in
CNI; configure it with a `KubeFlannelCNIConfig` document in `config_patches`.
`cilium` replaces Flannel and kube-proxy:

```hcl
module "talos" {
  # ...
  kubernetes_version = "1.36.6"
  cni = {
    name          = "cilium"
    configuration = [file("cilium-values.yaml")]
  }
}
```

The module renders the vendored Cilium chart (`deps/vendor/cilium`, pinned in
`deps/vendir.yml`) with `helm_template` and installs it as an inline manifest
on the control planes, so the CNI is running during bootstrap. It also deletes
the `KubeFlannelCNIConfig` document and disables kube-proxy
(`KubeProxyConfig` `enabled: false`) on the control planes.

`kubernetes_version` is required: the chart needs it to render.

## Values

Each `configuration` entry is a YAML document of Helm values, applied on top of
these base values:

| Value | Setting | Why |
| --- | --- | --- |
| `ipam.mode` | `kubernetes` | Talos assigns pod CIDRs to nodes |
| `kubeProxyReplacement` | `true` | kube-proxy is disabled |
| `k8sServiceHost` / `k8sServicePort` | `localhost` / `7445` | KubePrism, the API server on every node |
| `securityContext.capabilities.*` | Talos capability lists | Talos doesn't allow `SYS_MODULE` |
| `cgroup.autoMount.enabled` / `cgroup.hostRoot` | `false` / `/sys/fs/cgroup` | reuse the Talos cgroup mount |
| `hubble.tls.auto.method` | `cronJob` | see below |

**Rendering must be reproducible.** The chart's default for Hubble TLS
(`helm`) generates new certificates on every render, so every plan would
re-apply the node configuration. `cronJob` generates them in the cluster
instead. Any value that makes the chart generate random content (for example
other `tls.auto.method: helm` settings) has the same effect; avoid it.

## Changing the CNI

Switching `cni.name` on a running cluster is not supported. Switching away from
`cilium` and then running the sync command deletes the CNI and breaks pod
networking.

Upgrades, drift and the sync command work as for the addons; see
[Lifecycle](addons.md#lifecycle).
