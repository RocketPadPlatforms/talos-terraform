# Addons

Optional cluster components that the module installs as Talos inline manifests
on the control planes. Every addon is an object with `enabled` (default `false`)
plus its own settings:

```hcl
module "talos" {
  # ...
  addons = {
    kubelet_cert_approver  = { enabled = true }
    metrics_server         = { enabled = true }
    local_path_provisioner = { enabled = true, default_storage_class = true }
  }
}
```

The manifests are vendored in `deps/vendor/` and pinned in `deps/vendir.yml`.
Nodes download nothing at bootstrap.

## kubelet_cert_approver

Installs [kubelet-serving-cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver),
which approves the kubelets' serving certificate requests. It also sets
`serverTLSBootstrap: true` on all nodes, the same `KubeletConfig` patch as
`kubelet_server_tls_bootstrap` (see [Kubernetes nodes](kubernetes-nodes.md)).

On an existing cluster, turning it on changes the kubelet config on every node,
so each kubelet restarts once.

## metrics_server

Installs [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
(`components.yaml` from the release). metrics-server verifies kubelet
certificates, so enabling it also enables `kubelet_cert_approver`, whatever
`kubelet_cert_approver.enabled` says.

## local_path_provisioner

Installs [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
with two Talos changes: volumes live under `/var/mnt/local-path-provisioner`, and
the `local-path-storage` namespace allows privileged pods.

Every node gets a `UserVolumeConfig` named `local-path-provisioner` with
`volumeType: directory`. That directory sits on the system disk's EPHEMERAL
partition: volumes share space with container images and logs, and a full disk
puts the node under disk pressure.

To use a dedicated disk for a group instead, add a `UserVolumeConfig` with the
same name to the group's `config_patches`. Group patches apply after the
module's, so it overrides the directory volume:

```hcl
config_patches = [
  yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "local-path-provisioner"
    volumeType = "partition"
    provisioning = {
      diskSelector = { match = "disk.transport == \"nvme\" && !system_disk" }
      minSize      = "100GB"
    }
  })
]
```

`default_storage_class = true` marks the `local-path` StorageClass as the
cluster default. Only one StorageClass should be default.

## Lifecycle

Talos owns these components (and [Cilium](cilium.md)) after bootstrap. The
on-node manifest controller only creates missing objects. `talosctl upgrade-k8s`
re-applies every manifest with server-side apply, forcing the module's values,
and deletes objects whose manifest was removed. The `manifests_sync_command`
output is that command at the current Kubernetes version (it needs
`kubernetes_version`).

| Action | Steps |
| --- | --- |
| Install at bootstrap | Set the inputs and apply the module. |
| Install on an existing cluster | Set the inputs and apply the module; Talos creates the objects. Run the sync command afterwards to bring them under Talos's tracking. |
| Upgrade | Bump the version in `deps/vendir.yml` (Renovate opens these PRs), run `vendir sync` in `deps/`, apply the module, run the sync command with `--dry-run`, then without. |
| Remove | Set `enabled = false`, apply the module, run the sync command; Talos deletes the objects. |
| Drift | Each sync command run restores the module's state. |
| Kubernetes upgrade | `talosctl upgrade-k8s --to <new version>` also syncs the manifests. |

Rules:

- GitOps must not manage these components; the next sync overwrites its
  changes. Objects GitOps creates itself (for example Cilium LB pools) are fine.
- Objects installed by hand before an addon was enabled are taken over by Talos
  on the first sync.
- Turning off `local_path_provisioner` also removes its `UserVolumeConfig` from
  the nodes.

## Updating vendored content

```bash
cd deps
vendir sync      # after changing a version in vendir.yml
vendir sync -l   # what CI runs: re-sync from vendir.lock.yml, must not change files
```

Review and commit the diff in `deps/vendor/` together with `vendir.lock.yml`.
Never edit files in `deps/vendor/` by hand.
