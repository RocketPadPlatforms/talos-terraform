# Renewing an expired talosconfig

Talos client certificates (`talosconfig`, `kubeconfig`) do not auto-renew; the
client cert issued by this module expires (default validity ~24h–1y). When it
does, the module's `talosconfig` output stops working.

**Do NOT recreate `talos_machine_secrets`** (e.g. `tofu taint` or removing it).
Regenerating it produces a *new cluster CA*, which invalidates the certificate
trust on every node and forces a full reinstall. Renew or recover instead.

## 1. Renew while the current talosconfig is still valid

Mint a long-lived operator config against any control-plane node, then refresh
the `kubeconfig` (each fetch issues a fresh client cert):

```bash
talosctl -n <cp-ip> config new talosconfig \
  --roles os:admin --crt-ttl 8760h
talosctl kubeconfig
```

Consider doing this once right after the initial `tofu apply`, so the short-lived
module-issued config is only ever a bootstrap artifact.

## 2. Recover after it has expired (from the secrets bundle)

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

## 3. Recover from a control-plane machine configuration

If you have an original `controlplane.yaml` instead (e.g. saved during
bootstrap): re-derive the secrets from it, then re-issue the config.

```bash
talosctl gen secrets --from-controlplane-config controlplane.yaml
talosctl gen config \
  --with-secrets secrets.yaml --output-types talosconfig \
  -o talosconfig <cluster_name> https://<cluster_endpoint>
```

## Verify

```bash
talosctl --talosconfig talosconfig config info       # shows cert expiry/roles
talosctl -n <cp-ip> --talosconfig talosconfig version
```
