mock_provider "talos" {
  mock_data "talos_image_factory_urls" {
    defaults = {
      urls = {
        installer             = "factory.talos.dev/installer/abc123:v1.14.5"
        installer_secureboot  = "factory.talos.dev/installer-secureboot/abc123:v1.14.5"
        disk_image            = ""
        disk_image_secureboot = ""
        initramfs             = ""
        iso                   = ""
        iso_secureboot        = ""
        kernel                = ""
        kernel_command_line   = ""
        pxe                   = ""
        uki                   = ""
      }
    }
  }

  mock_data "talos_machine_configuration" {
    defaults = {
      machine_configuration = "version: v1alpha1\n"
    }
  }
}

mock_provider "helm" {
  mock_data "helm_template" {
    defaults = {
      manifest = "apiVersion: v1\nkind: ServiceAccount\nmetadata:\n  name: cilium\n  namespace: kube-system\n"
    }
  }
}

variables {
  talos_version      = "v1.14"
  kubernetes_version = "1.36.6"
  cluster_name       = "test"
}

run "basic_controlplane_and_worker" {
  command = apply

  variables {
    node_groups = {
      cp = {
        role               = "controlplane"
        image              = { version = "v1.14.5" }
        install_disk_match = "disk.dev_path == \"/dev/vda\""
        labels             = { "node.longhorn.io/create-default-disk" = "config" }
        nodes              = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition     = strcontains(output.installer_images.cp, "v1.14.5")
    error_message = "Factory group should resolve to the Factory installer URL."
  }

  assert {
    condition     = output.installer_images.wk == "factory.talos.dev/installer:v1.14.0"
    error_message = "Raw installer group should pass its image through unchanged."
  }

  assert {
    condition     = length(talos_image_factory_schematic.this) == 1 && contains(keys(talos_image_factory_schematic.this), "cp")
    error_message = "Only the Factory group should get a schematic."
  }

  assert {
    condition = (
      yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[1]).provisioning.diskSelector.match
      == "disk.dev_path == \"/dev/vda\""
    )
    error_message = "Group install_disk_match should reach the UnattendedInstallConfig patch."
  }

  assert {
    condition     = !can(yamldecode(talos_machine_configuration_apply.this["worker-w1"].config_patches[1]).provisioning)
    error_message = "Worker without install_disk_match must not get a diskSelector."
  }

  assert {
    condition = (
      yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[2]).labels["node.longhorn.io/create-default-disk"]
      == "config"
    )
    error_message = "Group labels should be rendered into a KubeNodeConfig patch."
  }

  assert {
    condition     = output.manifests_sync_command == "talosctl -n 10.0.0.1 upgrade-k8s --to 1.36.6"
    error_message = "Sync command should target the bootstrap node and the configured Kubernetes version."
  }
}

run "manifests_sync_command_without_version" {
  command = apply

  variables {
    kubernetes_version = null
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  assert {
    condition     = output.manifests_sync_command == null
    error_message = "Without kubernetes_version there is no version to sync to."
  }
}

run "node_overrides" {
  command = apply

  variables {
    node_groups = {
      cp = {
        role               = "controlplane"
        image              = { installer = "factory.talos.dev/installer:v1.14.0" }
        install_disk_match = "disk.dev_path == \"/dev/group\""
        labels             = { a = "group", b = "group" }
        annotations        = { x = "group" }
        taints             = { t1 = "NoSchedule" }
        nodes = {
          cp1 = {
            ip_address         = "10.0.0.1"
            install_disk_match = "disk.dev_path == \"/dev/node\""
            labels             = { b = "node", c = "node" }
            annotations        = { x = "node", y = "node" }
            taints             = { t1 = "v:NoExecute", t2 = "NoSchedule" }
          }
          cp2 = { ip_address = "10.0.0.2" }
        }
      }
    }
  }

  assert {
    condition = (
      yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[1]).provisioning.diskSelector.match
      == "disk.dev_path == \"/dev/node\""
    )
    error_message = "Node install_disk_match should replace the group value."
  }

  assert {
    condition = (
      yamldecode(talos_machine_configuration_apply.this["controlplane-cp2"].config_patches[1]).provisioning.diskSelector.match
      == "disk.dev_path == \"/dev/group\""
    )
    error_message = "Nodes without an override should inherit the group install_disk_match."
  }

  assert {
    condition = yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[2]).labels == {
      a = "group"
      b = "node"
      c = "node"
    }
    error_message = "Node labels should override group labels key by key."
  }

  assert {
    condition = yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[2]).annotations == {
      x = "node"
      y = "node"
    }
    error_message = "Node annotations should override group annotations key by key."
  }

  assert {
    condition = yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[2]).taints == {
      t1 = "v:NoExecute"
      t2 = "NoSchedule"
    }
    error_message = "Node taints should override group taints key by key."
  }

  assert {
    condition = yamldecode(talos_machine_configuration_apply.this["controlplane-cp2"].config_patches[2]).labels == {
      a = "group"
      b = "group"
    }
    error_message = "Nodes without overrides should inherit group labels."
  }

  assert {
    condition     = yamldecode(talos_machine_configuration_apply.this["controlplane-cp2"].config_patches[2]).taints == { t1 = "NoSchedule" }
    error_message = "Nodes without overrides should inherit group taints."
  }
}

run "scheduling_and_tls" {
  command = apply

  variables {
    allow_scheduling_on_controlplanes = true
    kubelet_server_tls_bootstrap      = true
    node_groups = {
      cp = {
        role   = "controlplane"
        image  = { installer = "factory.talos.dev/installer:v1.14.0" }
        taints = { dedicated = "NoSchedule" }
        nodes  = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition     = yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[2]).taints["$patch"] == "delete"
    error_message = "Controlplane should get the taint delete patch."
  }

  assert {
    condition     = yamldecode(talos_machine_configuration_apply.this["controlplane-cp1"].config_patches[3]).taints == { dedicated = "NoSchedule" }
    error_message = "Custom controlplane taint should survive, applied after the delete patch."
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      try(yamldecode(p).config.serverTLSBootstrap, false)
    ])
    error_message = "Controlplane should get the serverTLSBootstrap patch."
  }

  assert {
    condition = !anytrue([
      for p in talos_machine_configuration_apply.this["worker-w1"].config_patches :
      try(yamldecode(p).taints["$patch"] == "delete", false)
    ])
    error_message = "Workers must not get the taint delete patch."
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["worker-w1"].config_patches :
      try(yamldecode(p).config.serverTLSBootstrap, false)
    ])
    error_message = "Workers should get the serverTLSBootstrap patch."
  }
}

run "defaults_add_no_addon_patches" {
  command = apply

  variables {
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition = !anytrue(flatten([
      for key in ["controlplane-cp1", "worker-w1"] : [
        for p in talos_machine_configuration_apply.this[key].config_patches :
        contains(["KubeInlineManifestConfig", "UserVolumeConfig", "KubeFlannelCNIConfig", "KubeProxyConfig"], try(yamldecode(p).kind, ""))
      ]
    ]))
    error_message = "Defaults must not add addon or CNI patches."
  }
}

run "null_cni_and_addons_use_defaults" {
  command = apply

  variables {
    cni    = null
    addons = null
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  assert {
    condition = !anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      contains(["KubeInlineManifestConfig", "UserVolumeConfig", "KubeFlannelCNIConfig", "KubeProxyConfig"], try(yamldecode(p).kind, ""))
    ])
    error_message = "Null cni and addons must behave like the defaults."
  }
}

run "addons_metrics_server" {
  command = apply

  variables {
    addons = { metrics_server = { enabled = true } }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition = [
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      yamldecode(p).name if try(yamldecode(p).kind, "") == "KubeInlineManifestConfig"
    ] == ["kubelet-serving-cert-approver", "metrics-server"]
    error_message = "Controlplane should get the approver and metrics-server inline manifests."
  }

  assert {
    condition = length([
      for p in talos_machine_configuration_apply.this["worker-w1"].config_patches :
      p if try(yamldecode(p).kind, "") == "KubeInlineManifestConfig"
    ]) == 0
    error_message = "Workers must not get inline manifests."
  }

  assert {
    condition = alltrue([
      for key in ["controlplane-cp1", "worker-w1"] : anytrue([
        for p in talos_machine_configuration_apply.this[key].config_patches :
        try(yamldecode(p).config.serverTLSBootstrap, false)
      ])
    ])
    error_message = "metrics-server should enable serverTLSBootstrap on all nodes."
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      try(yamldecode(p).name, "") == "metrics-server" && strcontains(yamldecode(p).manifest, "kind: Deployment")
    ])
    error_message = "The metrics-server inline manifest should contain the vendored Deployment."
  }
}

run "addons_cert_approver_only" {
  command = apply

  variables {
    addons = { kubelet_cert_approver = { enabled = true } }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition = [
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      yamldecode(p).name if try(yamldecode(p).kind, "") == "KubeInlineManifestConfig"
    ] == ["kubelet-serving-cert-approver"]
    error_message = "Controlplane should get only the approver inline manifest."
  }

  assert {
    condition = alltrue([
      for key in ["controlplane-cp1", "worker-w1"] : anytrue([
        for p in talos_machine_configuration_apply.this[key].config_patches :
        try(yamldecode(p).config.serverTLSBootstrap, false)
      ])
    ])
    error_message = "The approver should enable serverTLSBootstrap on all nodes."
  }
}

run "addons_tls_bootstrap_not_duplicated" {
  command = apply

  variables {
    kubelet_server_tls_bootstrap = true
    addons                       = { metrics_server = { enabled = true } }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  assert {
    condition = length([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      p if try(yamldecode(p).kind, "") == "KubeletConfig"
    ]) == 1
    error_message = "Exactly one KubeletConfig patch expected."
  }
}

run "addons_local_path_provisioner" {
  command = apply

  variables {
    addons = { local_path_provisioner = { enabled = true } }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        config_patches = [
          yamlencode({
            apiVersion = "v1alpha1"
            kind       = "UserVolumeConfig"
            name       = "local-path-provisioner"
            volumeType = "partition"
          })
        ]
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition = alltrue([
      for key in ["controlplane-cp1", "worker-w1"] : anytrue([
        for p in talos_machine_configuration_apply.this[key].config_patches :
        try(yamldecode(p).kind == "UserVolumeConfig" && yamldecode(p).name == "local-path-provisioner" && yamldecode(p).volumeType == "directory", false)
      ])
    ])
    error_message = "All nodes should get the local-path-provisioner directory volume."
  }

  assert {
    condition = (
      index([for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches : try(yamldecode(p).volumeType, "")], "directory")
      < index([for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches : try(yamldecode(p).volumeType, "")], "partition")
    )
    error_message = "Group patches must come after the module volume so they can override it."
  }

  assert {
    condition = [
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      yamldecode(p).name if try(yamldecode(p).kind, "") == "KubeInlineManifestConfig"
    ] == ["local-path-provisioner"]
    error_message = "Controlplane should get the local-path-provisioner inline manifest."
  }

  assert {
    condition = length([
      for p in talos_machine_configuration_apply.this["worker-w1"].config_patches :
      p if try(yamldecode(p).kind, "") == "KubeInlineManifestConfig"
    ]) == 0
    error_message = "Workers must not get inline manifests."
  }

  assert {
    condition     = length([for d in split("\n---\n", local.local_path_provisioner_manifest) : d if trimspace(d) != ""]) == 9
    error_message = "All 9 upstream documents must be kept."
  }

  assert {
    condition = one([
      for d in split("\n---\n", local.local_path_provisioner_manifest) :
      jsondecode(yamldecode(d).data["config.json"]).nodePathMap[0].paths if try(yamldecode(d).kind, "") == "ConfigMap"
    ]) == ["/var/mnt/local-path-provisioner"]
    error_message = "Provisioner path should be the Talos user volume mount."
  }

  assert {
    condition = one([
      for d in split("\n---\n", local.local_path_provisioner_manifest) :
      yamldecode(d).metadata.labels["pod-security.kubernetes.io/enforce"] if try(yamldecode(d).kind, "") == "Namespace"
    ]) == "privileged"
    error_message = "Namespace should allow privileged pods."
  }

  assert {
    condition = !anytrue([
      for d in split("\n---\n", local.local_path_provisioner_manifest) :
      can(yamldecode(d).metadata.annotations["storageclass.kubernetes.io/is-default-class"]) if try(yamldecode(d).kind, "") == "StorageClass"
    ])
    error_message = "StorageClass must not be default unless requested."
  }

  assert {
    condition = (
      one([for d in split("\n---\n", local.local_path_provisioner_manifest) : yamldecode(d) if try(yamldecode(d).kind, "") == "Deployment"])
      == one([for d in split("\n---\n", file("deps/vendor/addons/local-path-provisioner/deploy/local-path-storage.yaml")) : yamldecode(d) if try(yamldecode(d).kind, "") == "Deployment"])
    )
    error_message = "Untouched documents must stay equal to upstream."
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      try(yamldecode(p).manifest == local.local_path_provisioner_manifest, false)
    ])
    error_message = "The inline manifest should carry the transformed manifest."
  }
}

run "addons_local_path_provisioner_default_class" {
  command = apply

  variables {
    addons = { local_path_provisioner = { enabled = true, default_storage_class = true } }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  assert {
    condition = one([
      for d in split("\n---\n", local.local_path_provisioner_manifest) :
      yamldecode(d).metadata.annotations["storageclass.kubernetes.io/is-default-class"] if try(yamldecode(d).kind, "") == "StorageClass"
    ]) == "true"
    error_message = "StorageClass should be marked default."
  }
}

run "cilium" {
  command = apply

  variables {
    cni    = { name = "cilium", configuration = ["hubble:\n  relay:\n    enabled: true\n"] }
    addons = { metrics_server = { enabled = true } }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "factory.talos.dev/installer:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      try(yamldecode(p).kind == "KubeFlannelCNIConfig" && yamldecode(p)["$patch"] == "delete", false)
    ])
    error_message = "Controlplane should delete the Flannel CNI config."
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      try(yamldecode(p).kind == "KubeProxyConfig" && yamldecode(p).enabled == false, false)
    ])
    error_message = "Controlplane should disable kube-proxy."
  }

  assert {
    condition = anytrue([
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      try(yamldecode(p).name == "cilium" && strcontains(yamldecode(p).manifest, "name: cilium"), false)
    ])
    error_message = "Controlplane should get the rendered cilium inline manifest."
  }

  assert {
    condition = [
      for p in talos_machine_configuration_apply.this["controlplane-cp1"].config_patches :
      yamldecode(p).name if try(yamldecode(p).kind, "") == "KubeInlineManifestConfig"
    ] == ["cilium", "kubelet-serving-cert-approver", "metrics-server"]
    error_message = "Cilium should come before the addon manifests."
  }

  assert {
    condition = !anytrue([
      for p in talos_machine_configuration_apply.this["worker-w1"].config_patches :
      contains(["KubeFlannelCNIConfig", "KubeProxyConfig", "KubeInlineManifestConfig"], try(yamldecode(p).kind, ""))
    ])
    error_message = "Workers must not get CNI patches."
  }
}

run "cilium_requires_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = null
    cni                = { name = "cilium" }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "x" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [data.helm_template.cilium]
}

run "validation_cni_name" {
  command = plan

  variables {
    cni = { name = "calico" }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "x" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [var.cni]
}

run "validation_cni_flannel_configuration" {
  command = plan

  variables {
    cni = { configuration = ["a: b\n"] }
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "x" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [var.cni]
}

run "validation_role" {
  command = plan

  variables {
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "test:v1.14.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
      bad = {
        role  = "invalid"
        image = { installer = "test:v1.14.0" }
        nodes = { w1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "validation_factory_version_floor" {
  command = plan

  variables {
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { version = "v1.12.0" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "validation_unique_names" {
  command = plan

  variables {
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "x" }
        nodes = { n1 = { ip_address = "10.0.0.1" } }
      }
      wk = {
        role  = "worker"
        image = { installer = "x" }
        nodes = { n1 = { ip_address = "10.0.0.2" } }
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "validation_image_both" {
  command = plan

  variables {
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { version = "v1.14.5", installer = "x" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "validation_talos_version" {
  command = plan

  variables {
    talos_version = "v1.12"
    node_groups = {
      cp = {
        role  = "controlplane"
        image = { installer = "x" }
        nodes = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [var.talos_version]
}

run "validation_taint_effect" {
  command = plan

  variables {
    node_groups = {
      cp = {
        role   = "controlplane"
        image  = { installer = "x" }
        taints = { t = "Bogus" }
        nodes  = { cp1 = { ip_address = "10.0.0.1" } }
      }
    }
  }

  expect_failures = [var.node_groups]
}
