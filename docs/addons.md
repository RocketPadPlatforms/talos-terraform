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
    control_plane_metrics  = { enabled = true }
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
module's, so it overrides the directory volume. Set `volumeType: partition`
explicitly: the patch is merged onto the module's `volumeType: directory`, and
Talos rejects `provisioning` on a directory volume.

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

## control_plane_metrics

Makes the control-plane metrics that Talos keeps on loopback reachable for an
in-cluster collector (Prometheus Operator, Grafana Alloy). It ships no
`ServiceMonitor`: the CRDs do not exist at bootstrap.

On control planes it sets:

| Component | Setting | Port |
| --- | --- | --- |
| etcd | `listen-metrics-urls: http://0.0.0.0:2381` in `cluster.etcd.extraArgs`, or in `EtcdMemberConfig` when the generated config has one (Talos 1.15 contract) | `2381` (HTTP, no auth) |
| kube-controller-manager | `bind-address: 0.0.0.0` in `KubeControllerManagerConfig` | `10257` (HTTPS, token) |
| kube-scheduler | `bind-address: 0.0.0.0` in `KubeSchedulerConfig` | `10259` (HTTPS, token) |

To change one of these values, patch the same document again (see
[overriding module documents](config-patches.md#overriding-module-documents)).

and installs headless discovery Services in `kube-system`, laid out like
[kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)'s
kubeadm platform:

| Service | Label `app.kubernetes.io/name` | Port name |
| --- | --- | --- |
| `kube-controller-manager-prometheus-discovery` | `kube-controller-manager` | `https-metrics` |
| `kube-scheduler-prometheus-discovery` | `kube-scheduler` | `https-metrics` |
| `kube-etcd-prometheus-discovery` | `etcd` | `http-metrics` |

etcd runs outside Kubernetes, so its Service selects the controller-manager
pods: they use the host network on every control plane, which gives the same
endpoint addresses.

### Firewall

A `NetworkRuleConfig` named `control-plane-metrics-ingress` drops traffic to
`2381`, `10257` and `10259` unless it comes from a node `ip_address` or from
`allowed_subnets` (default `["10.244.0.0/16"]`, the Talos pod CIDR). All other
ports keep their current behaviour. Set `allowed_subnets` when:

- the cluster uses a different or additional (e.g. IPv6) pod CIDR;
- a node's `ip_address` is not the address it uses inside the cluster (add the
  node network).

Every node `ip_address` must be an IP address while the addon is enabled. Add
sources through `allowed_subnets`: patching `control-plane-metrics-ingress`
with your own `ingress` replaces the whole list, node IPs included.

Flannel masquerades pod traffic to the node IP, Cilium keeps the pod IP; the
defaults cover both. Cilium's host firewall, if enabled, bypasses Talos rules.

### Existing clusters

The controller-manager and scheduler restart with the new address when the
config is applied. Run the sync command afterwards so Talos tracks the
Services.

- Talos 1.14 (`cluster.etcd`): the config is applied without a reboot, and etcd
  only opens the metrics port after the next one. Reboot the control planes one
  at a time (`talosctl reboot -n <ip>`) and check etcd health in between.
- Talos 1.15 contract (`EtcdMemberConfig`): etcd restarts as soon as the config
  is applied, and Talos does not coordinate the restarts across nodes, so all
  control planes may restart etcd at once. Enable the addon with
  `apply_mode = "staged"`, then reboot the control planes one at a time.

### Scraping

Prometheus Operator / Grafana Alloy (`prometheus.operator.servicemonitors`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kube-scheduler
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kube-scheduler
  endpoints:
    - port: https-metrics
      scheme: https
      bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
      tlsConfig:
        insecureSkipVerify: true # self-signed serving certificate
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: etcd
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: etcd
  endpoints:
    - port: http-metrics
```

The controller-manager works like the scheduler. The scraper's service account
needs `get` on the non-resource URL `/metrics`.

kube-prometheus-stack creates its own Services. Its controller-manager and
scheduler selectors already match Talos, and it scrapes etcd on `2381`; only
the etcd selector needs a value:

```yaml
kubeEtcd:
  service:
    selector:
      component: kube-controller-manager
```

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
  the nodes. Back up the data of its PersistentVolumes first: it is not
  documented whether Talos keeps the data under `/var/mnt/local-path-provisioner`.

## Updating vendored content

```bash
cd deps
vendir sync      # after changing a version in vendir.yml
vendir sync -l   # what CI runs: re-sync from vendir.lock.yml, must not change files
```

Review and commit the diff in `deps/vendor/` together with `vendir.lock.yml`.
Never edit files in `deps/vendor/` by hand.
