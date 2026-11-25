# Changelog

## [1.2.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v1.1.0...v1.2.0) (2026-11-25)


### Features

* **addons:** add control-plane metrics addon ([4f8c164](https://github.com/RocketPadPlatforms/talos-terraform/commit/4f8c164746c6268988dc36ced0152699e083251e))

## [1.1.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v1.0.1...v1.1.0) (2026-11-10)


### Features

* **talos:** add optional node hostname ([803e69d](https://github.com/RocketPadPlatforms/talos-terraform/commit/803e69daa58735295f68c56660a67326ff95b92b))

## [1.0.1](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.3.0...v1.0.1) (2026-11-10)


### ⚠ BREAKING CHANGES

* **talos:** node_data is replaced by node_groups, config_patches_* by config_patches, install_disk/install_disk_selector/install_image by node_groups image specs and install_disk_match. Provider >= 0.12.0 and talos_version >= v1.14 are now required. See README upgrade guide.

### Features

* **addons:** add cert approver and metrics-server ([ec899e7](https://github.com/RocketPadPlatforms/talos-terraform/commit/ec899e7b478e1c4a8d3cfa6e4c1c03380b6a187b))
* **addons:** add local-path-provisioner ([d51eec6](https://github.com/RocketPadPlatforms/talos-terraform/commit/d51eec6f41a916f548370bae9d6361546077a782))
* **cilium:** add optional cilium cni ([f519e55](https://github.com/RocketPadPlatforms/talos-terraform/commit/f519e55747e13011f14e78bb9010a1e60a7aba14))
* **talos:** add per-group disk encryption ([d00fdd9](https://github.com/RocketPadPlatforms/talos-terraform/commit/d00fdd94855016a6317bd3ad454fd6c2465bcc7e))
* **talos:** emit Talos 1.14 config documents ([f3fb883](https://github.com/RocketPadPlatforms/talos-terraform/commit/f3fb883d247b81d059193b64842f81fa56b8518d))
* **talos:** output manifest sync command ([88d7e93](https://github.com/RocketPadPlatforms/talos-terraform/commit/88d7e93f7986c2889c1c5a7e3aed7ca0a7867408))


### Bug Fixes

* **addons:** pin local-path helper image ([a891c80](https://github.com/RocketPadPlatforms/talos-terraform/commit/a891c802b8ba27f1137af978c8f4dd945f355253))
* **addons:** treat null addons and cni as defaults ([d0887e2](https://github.com/RocketPadPlatforms/talos-terraform/commit/d0887e22b30b1cc35c14bc5ad82cfe694caf94ea))

## [0.3.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.2.0...v0.3.0) (2026-09-10)


### Features

* **talos:** allow disabling the cluster health check ([db31891](https://github.com/RocketPadPlatforms/talos-terraform/commit/db31891cee83d69dfcd4eddd040ca5167ad13779))

## [0.2.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.1.18...v0.2.0) (2026-09-08)


### Features

* replace GitLab CI with GitHub Actions CI and release-please ([f1ef308](https://github.com/RocketPadPlatforms/talos-terraform/commit/f1ef3081ea6e11998ba2dd7b3f12d42e687c8cb0))
