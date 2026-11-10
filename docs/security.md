# Security

What the module protects, what it leaves to you, and how to harden a cluster
built with it.

## Terraform state and outputs

The module's state is highly sensitive: it stores the generated Talos machine
secrets (including the cluster CA private keys) and the cluster `kubeconfig` in
plaintext. Treat state like a credential:

- **Use an encrypted remote backend for production.** Prefer Terraform/OpenTofu
  cloud backends or an S3/GCS/Azure backend with server-side encryption (KMS)
  enabled, and enable state locking. Avoid the default local backend with state
  on shared or untracked disk.
- **Restrict state access.** Only operators who need cluster administration
  rights should be able to read state, backups, or the outputs.
- **Protect operator credentials.** Lock down the OpenTofu CLI configuration
  and any cloud/provider credentials on machines running `tofu apply`. Never
  commit `*.tfvars` (local overrides are already gitignored).
- **Sensitive outputs.** The `talosconfig`, `talos_machine_secrets`,
  `kubeconfig` and `kubernetes_client_configuration` outputs are
  `sensitive = true` and are not printed in plans or console output; avoid
  piping them into logs or files outside the state/backend. Only pass
  `talos_machine_secrets` on where it is really needed: whoever holds it can
  issue admin credentials for the cluster.

Client certificates expire; see
[Renewing an expired talosconfig](talosconfig-renewal.md). Never recreate
`talos_machine_secrets` on a running cluster.

## Bootstrap in maintenance mode

Nodes start in maintenance mode, which accepts a machine configuration from
anyone, without authentication. The first apply sends the full configuration,
including the cluster CA keys on control planes. Anyone on the same network
can read it or push their own configuration first.

Provision nodes only on a trusted, isolated network (a dedicated provisioning
VLAN, or a host firewall that only lets the operator reach port `50000`), and
expose them more widely only after the first apply.

## Network exposure

The module adds no firewall. By default every node accepts connections from
any network it can reach, including:

| Port | Service | Nodes |
|---|---|---|
| `50000/tcp` | Talos API (`apid`) | all |
| `50001/tcp` | `trustd` | control planes |
| `6443/tcp` | Kubernetes API | control planes |
| `2379-2380/tcp` | etcd | control planes |
| `10250/tcp` | kubelet | all |

All of them require client certificates, but limiting who can reach them
shrinks the attack surface. Talos has an ingress firewall configured through
`NetworkDefaultActionConfig` and `NetworkRuleConfig` documents. A worker group
that only accepts Talos API and kubelet traffic from the cluster network:

```hcl
workers = {
  role  = "worker"
  image = { version = "v1.14.5" }
  config_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "NetworkDefaultActionConfig", ingress = "block" }),
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "NetworkRuleConfig"
      name         = "apid-ingress"
      portSelector = { ports = [50000], protocol = "tcp" }
      ingress      = [{ subnet = "10.0.0.0/16" }]
    }),
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "NetworkRuleConfig"
      name         = "kubelet-ingress"
      portSelector = { ports = [10250], protocol = "tcp" }
      ingress      = [{ subnet = "10.0.0.0/16" }]
    }),
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "NetworkRuleConfig"
      name         = "cni-vxlan"
      portSelector = { ports = [4789], protocol = "udp" } # Cilium: 8472
      ingress      = [{ subnet = "10.0.0.0/16" }]
    }),
  ]
  nodes = { w1 = { ip_address = "10.0.1.1" } }
}
```

The machine running `tofu apply` must still reach port `50000` on every node,
and control planes need the rules from the Talos
[Ingress Firewall](https://docs.siderolabs.com/talos/v1.14/networking/ingress-firewall)
guide (Kubernetes API, `trustd`, etcd). A wrong rule can lock you out of the
Talos API: try it on one node first, with `apply_mode = "staged"` and a manual
`talosctl apply-config --mode=try`.

## Disk encryption

Talos does not encrypt disks by default. `STATE` holds the machine
configuration (on control planes: the cluster CA keys and etcd secrets) and
`EPHEMERAL` holds container data, logs and etcd data. Anyone with the disk can
read both.

Turn on LUKS2 encryption for both volumes per node group:

```hcl
cp = {
  role            = "controlplane"
  image           = { version = "v1.14.5", secureboot = true }
  disk_encryption = { method = "tpm" }
  nodes           = { c1 = { ip_address = "10.0.0.1" } }
}
```

`method` decides where the key comes from:

| `method` | Protects against | Requirements |
|---|---|---|
| `tpm` | Stolen disks and stolen machines (with SecureBoot) | TPM 2.0 and SecureBoot. Image Factory groups must set `image.secureboot = true` |
| `kms` | Stolen disks and stolen machines | `kms_endpoint` (`https://`), reachable from the node before `STATE` unlocks |
| `nodeID` | Disks removed from the machine only. The key is derived from the node UUID, so a stolen machine decrypts itself | none |

With `kms`, network settings cannot come from the machine configuration (they
are stored in `STATE`, which is still locked), and the KMS server cannot use a
custom CA. Static passphrases are not offered: for `STATE` Talos would store
them in cleartext on the `META` partition.

The module adds a `VolumeConfig` document for `STATE` and `EPHEMERAL` with one
key in slot 0:

- `EPHEMERAL` uses `lockToState: true`: if `STATE` is wiped or replaced,
  `EPHEMERAL` can no longer be unlocked.
- `tpm` keys set `checkSecurebootStatusOnEnroll: true`, so enrolment fails on
  a node with SecureBoot off. This also covers groups with a raw `installer`
  image, which the module cannot check at plan time.
- TPM keys use the Talos default PCRs.

### Overriding the generated documents

Talos appends list entries when it merges patches, so a second `STATE`
document would add a second slot-0 key and fail validation. To change the
generated configuration (for example the TPM PCRs), delete the module's
document and supply a full replacement, as two separate patches:

```hcl
config_patches = [
  yamlencode({ apiVersion = "v1alpha1", kind = "VolumeConfig", name = "STATE", "$patch" = "delete" }),
  yamlencode({
    apiVersion = "v1alpha1"
    kind       = "VolumeConfig"
    name       = "STATE"
    encryption = {
      provider = "luks2"
      keys     = [{ slot = 0, tpm = { checkSecurebootStatusOnEnroll = true, options = { pcrs = [7, 11] } } }]
    }
  }),
]
```

### Dedicated system volumes

`ETCD`, `CRI`, `KUBELET` and `LOG` live in directories on `EPHEMERAL` by
default and are encrypted with it. If you move one to its own partition (see
[System Volumes](https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/storage-and-disk-management/disk-management/system#dedicated-system-volumes-etcd-cri-kubelet-log)),
it is a separate LUKS volume and **is not encrypted unless its own
`VolumeConfig` has an `encryption` block**. The module does not add one; put it
in the same document that creates the partition:

```hcl
config_patches = [
  yamlencode({
    apiVersion = "v1alpha1"
    kind       = "VolumeConfig"
    name       = "ETCD"
    provisioning = {
      diskSelector = { match = "disk.transport == 'nvme' && !system_disk" }
      minSize      = "2GB"
      maxSize      = "10GB"
    }
    encryption = {
      provider = "luks2"
      keys     = [{ slot = 0, lockToState = true, tpm = {} }]
    }
  }),
]
```

Use the same method as the group's `disk_encryption`, with `lockToState: true`.
The `local-path-provisioner` addon volume is a directory on `EPHEMERAL` and is
covered by `EPHEMERAL` encryption.

### Existing nodes

**Never add, remove or change `disk_encryption` on a group whose nodes are
already provisioned.** Talos encrypts a volume only when it is empty. A node
whose existing, unencrypted volume suddenly has an encryption config (or whose
encrypted volume loses it) fails to bring the volume up with
`block dev type mismatch` on its next reboot, which may be an upgrade, a power
loss or a crash. The same goes for changing `method` or `kms_endpoint`: the key
in slot 0 is replaced, and the new key cannot unlock the volume.

To encrypt running nodes, create a new group with `disk_encryption` and move
the nodes into it one at a time, each with two separate applies (moving a node
between groups of the same role in a single apply only changes its config,
which is exactly the mismatch above):

1. Drain the node (`kubectl drain`). For a control plane, make it leave etcd
   while it still works: `talosctl -n <ip> etcd leave`. Only do this with at
   least three control planes; a single control plane cannot be migrated this
   way, and two would lose quorum.
2. Remove the node from the old group and `tofu apply`. The module resets the
   node, which wipes `STATE` and `EPHEMERAL` (including local-path volumes)
   and returns it to maintenance mode. Removing the first control plane (by
   name) also moves the bootstrap and kubeconfig target to another node;
   review the plan before applying.
3. The reset does not touch dedicated system volumes. If the node has any,
   wipe their partitions now, in maintenance mode:
   `talosctl -n <ip> wipe disk --insecure <partition>` (find them with
   `talosctl -n <ip> get discoveredvolumes --insecure`).
4. Add the node to the new group and `tofu apply`. It is provisioned with
   encrypted volumes. Check with `talosctl -n <ip> get volumestatus`.

## SecureBoot

`image.secureboot = true` installs a signed Unified Kernel Image (UKI) from the
Image Factory and makes the module use `installer_secureboot` (see
[Images](images.md)). The firmware must have SecureBoot enabled and the Talos
keys enrolled; see the Talos
[SecureBoot](https://docs.siderolabs.com/talos/v1.14/platform-specific-installations/bare-metal-platforms/secureboot)
guide. Without SecureBoot a TPM key is not tied to a trusted boot chain.

## Traffic between nodes

Pod, service and node traffic between nodes is not encrypted by default. Two
opt-in options:

- **Cilium WireGuard** (with `cni.name = "cilium"`): add
  `"encryption:\n  enabled: true\n  type: wireguard\n"` to `cni.configuration`.
  It encrypts pod traffic between nodes. Allow UDP `51871` between nodes if
  you use the ingress firewall.
- **KubeSpan**: a Talos WireGuard mesh between nodes, enabled with a
  `KubeSpanConfig` document (`enabled = true`) in `config_patches`. It uses the
  Sidero Labs discovery service by default. See
  [KubeSpan](https://docs.siderolabs.com/talos/v1.14/networking/kubespan),
  including its notes on Cilium.

Control-plane traffic (Talos API, Kubernetes API, etcd, kubelet) always uses
mutual TLS.

## Kubernetes secrets and pod security

- **Secrets at rest.** Talos encrypts Kubernetes `Secret` objects in etcd with
  a key from the machine secrets. Encrypt `EPHEMERAL` (or a dedicated `ETCD`
  volume) as well, so the etcd data on disk is protected too.
- **Pod Security Admission.** Talos enforces the `baseline` profile in every
  namespace except `kube-system` and warns on `restricted`. The
  `local-path-provisioner` addon labels its namespace `privileged` because its
  helper pods need host paths. See
  [Pod Security](https://docs.siderolabs.com/kubernetes-guides/security/pod-security).

## Supply chain and patching

- **Vendored content.** The Cilium chart and addon manifests are vendored in
  `deps/vendor/` and pinned in `deps/vendir.lock.yml`; CI fails if the vendored
  files drift from the lock file. Images inside the upstream manifests are
  pinned by tag; the `local-path-provisioner` helper image is pinned by tag
  and digest.
- **Renovate** updates providers, the Nix flake, GitHub Actions and the pinned
  helper image.
- **Providers.** `version.tf` sets minimum versions only. Commit
  `.terraform.lock.hcl` in your root module so provider checksums are pinned.
- **Patching nodes.** Changing `image` does not upgrade running nodes; upgrade
  them with `talosctl upgrade` (see [Images](images.md)) and Kubernetes with
  `talosctl upgrade-k8s`.
