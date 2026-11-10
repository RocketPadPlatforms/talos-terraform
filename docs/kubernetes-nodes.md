# Kubernetes nodes

Labels, annotations and taints are set per group and per node (the node wins on
conflict, see [Node groups](node-groups.md)). The module renders them into one
`KubeNodeConfig` document per node:

```hcl
node_groups = {
  gpu = {
    role        = "worker"
    image       = { version = "v1.14.5" }
    labels      = { "example.com/pool" = "gpu" }
    annotations = { "example.com/owner" = "ml-team" }
    taints      = { gpu = "true:NoSchedule" }
    nodes = {
      g1 = { ip_address = "10.0.2.1" }
    }
  }
}
```

## Taints

The map key is the taint key and the value is `[<value>:]<effect>`. The effect is
`NoSchedule`, `PreferNoSchedule` or `NoExecute`. `infra = "NoSchedule"` is a taint
without a value; `gpu = "true:NoSchedule"` has the value `true`. Other formats
fail validation.

**Worker taints only apply at registration.** The kubelet sets taints when it
registers the node. Changing taints on a node that is already registered
doesn't update the Node object. Apply the change with `kubectl taint`, or reset
and rejoin the node.

## Labels

Kubelets can only set certain labels on their own Node (the `NodeRestriction`
admission plugin). Labels in the `kubernetes.io/` and `k8s.io/` namespaces are
rejected at registration, including `node-role.kubernetes.io/*`, except for a
fixed allowed set: `kubernetes.io/hostname`, `kubernetes.io/arch`,
`kubernetes.io/os`, `topology.kubernetes.io/region`,
`topology.kubernetes.io/zone`, `node.kubernetes.io/instance-type`, and anything
under `kubelet.kubernetes.io/` or `node.kubernetes.io/`. Use your own domain, for
example `example.com/pool`. Set restricted labels with `kubectl label` instead.

## Scheduling on controlplanes

Controlplanes carry a `NoSchedule` taint by default. Set
`allow_scheduling_on_controlplanes = true` to remove it, for example on small
clusters where controlplanes also run workloads. The generated taint is removed
with a `KubeNodeConfig` `taints: {$patch: delete}` patch; taints you set on the
controlplane group or node are kept.

## Kubelet server TLS bootstrap

`kubelet_server_tls_bootstrap = true` sets `KubeletConfig`
`serverTLSBootstrap: true` on all nodes. Kubelets then request their serving
certificate through a CSR, and nothing approves those automatically. Install a
CSR approver such as
[kubelet-serving-cert-approver](https://github.com/alex1989hu/kubelet-serving-cert-approver)
or the cluster will have pending CSRs and broken `kubectl logs`/`exec`.
