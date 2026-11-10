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
