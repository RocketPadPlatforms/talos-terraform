# Talos

This repository contains a Terraform module to deploy a Kubernetes cluster using
[Talos](https://www.talos.dev/).


## Requirements

- Server(s) with booted Talos in maintenance mode


## Usage

```
module "talos" {
  source  = "path/to/talos"

  cluster_name = "my-cluster"
  node_data = {
    controlplanes = {
      "my-cluster-c1" = {
        ip_address   = "192.168.1.1"
        install_disk = "/dev/sda"
      }
    }
    workers = {
      "my-cluster-w1" = {
        ip_address   = "192.168.1.2"
        install_disk = "/dev/sda"
      }
    }
  }
  config_patches_controlplane = [
    "path/to/my-patch-cp-a.yaml",
    "path/to/my-patch-cp-b.yaml"
  ]
  config_patches_worker = [
    "path/to/my-patch-worker-a.yaml",
    "path/to/my-patch-worker-b.yaml"
  ]
  config_patches_all = [
    "path/to/my-patch-all-a.yaml",
    "path/to/my-patch-all-b.yaml"
  ]
}
```


## Security

The module's state is highly sensitive: it stores the generated Talos machine
secrets and the cluster `kubeconfig` in plaintext. Treat state like a credential:

- **Use an encrypted remote backend for production.** Prefer Terraform/OpenTofu
  cloud backends or an S3/GCS/Azure backend with server-side encryption (KMS)
  enabled, and enable state locking. Avoid the default local backend with state
  on shared or untracked disk.
- **Restrict state access.** Only operators who need cluster administration
  rights should be able to read state, backups, or the outputs.
- **Protect operator credentials.** Lock down the OpenTofu CLI configuration
  and any cloud/provider credentials on machines running `tofu apply`. Never
  commit `*.tfvars` (local overrides are already gitignored).
- **Sensitive outputs.** All module outputs (`talosconfig`, machine secrets,
  `kubeconfig`) are `sensitive = true` and are not printed in plans or console
  output; avoid piping them into logs or files outside the state/backend.


## Renewing an expired talosconfig

Talos client certificates (`talosconfig`, `kubeconfig`) do not auto-renew; the
client cert issued by this module expires (default validity ~24h–1y). When it
does, the module's `talosconfig` output stops working.

**Do NOT recreate `talos_machine_secrets`** (e.g. `tofu taint` or removing it).
Regenerating it produces a *new cluster CA*, which invalidates the certificate
trust on every node and forces a full reinstall. Renew or recover instead.

### 1. Renew while the current talosconfig is still valid

Mint a long-lived operator config against any control-plane node, then refresh
the `kubeconfig` (each fetch issues a fresh client cert):

```bash
talosctl -n <cp-ip> config new talosconfig \
  --roles os:admin --crt-ttl 8760h
talosctl kubeconfig
```

Consider doing this once right after the initial `tofu apply`, so the short-lived
module-issued config is only ever a bootstrap artifact.

### 2. Recover after it has expired (from the secrets bundle)

The module persists the machine secrets in state (`module.talos`), which is all
that is needed to re-issue a valid `talosconfig` for the existing cluster.

```bash
# Export the secrets bundle from the consumer root module
tofu output -raw talos_machine_secrets | yq -P > secrets.yaml

# Regenerate the talosconfig from the same cluster secrets
talosctl gen config \
  --with-secrets secrets.yaml \
  --output-types talosconfig \
  -o talosconfig <cluster_name> https://<cluster_endpoint>
```

`<cluster_endpoint>` is `module "talos"`'s `cluster_endpoint` variable or, if
unset, `https://<first-controlplane-ip>:6443`. The re-issued cert is signed by
the existing cluster CA, so nodes accept it immediately.

### 3. Recover from a control-plane machine configuration

If you have an original `controlplane.yaml` instead (e.g. saved during
bootstrap): re-derive the secrets from it, then re-issue the config.

```bash
talosctl gen secrets --from-controlplane-config controlplane.yaml
talosctl gen config \
  --with-secrets secrets.yaml --output-types talosconfig \
  -o talosconfig <cluster_name> https://<cluster_endpoint>
```

### Verify

```bash
talosctl --talosconfig talosconfig config info       # shows cert expiry/roles
talosctl -n <cp-ip> --talosconfig talosconfig version
```
