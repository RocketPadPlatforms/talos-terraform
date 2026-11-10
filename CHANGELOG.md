# Changelog

## [1.0.1](https://github.com/RocketPadPlatforms/talos-terraform/compare/v1.0.0...v1.0.1) (2026-11-10)


### ⚠ BREAKING CHANGES

* **talos:** node_data is replaced by node_groups, config_patches_* by config_patches, install_disk/install_disk_selector/install_image by node_groups image specs and install_disk_match. Provider >= 0.12.0 and talos_version >= v1.14 are now required. See README upgrade guide.
* **talos:** resource addresses changed from talos_machine_configuration_apply.controlplane["<name>"] and .worker["<name>"] to talos_machine_configuration_apply.this["..."]. Consumers with existing state must run tofu state mv for each node instance before re-applying, or nodes will be recreated.
* **nodes:** swap hostname and address
* **configpatches:** Allow configuring config patches for workers

### docs

* **changelog:** drop unreleased 1.0.0 entry ([c44487d](https://github.com/RocketPadPlatforms/talos-terraform/commit/c44487d51b5bba99c1947da7d237456e81aa5202))


### refactor

* **nodes:** swap hostname and address ([45ccbd8](https://github.com/RocketPadPlatforms/talos-terraform/commit/45ccbd842198c4f6f4c3dc138eb2849b0c92d6e5))
* **talos:** unify controlplane/worker apply config ([c20a655](https://github.com/RocketPadPlatforms/talos-terraform/commit/c20a6558e1fede634a668fac13c39130a199477a))


### Features

* **addons:** add cert approver and metrics-server ([ec899e7](https://github.com/RocketPadPlatforms/talos-terraform/commit/ec899e7b478e1c4a8d3cfa6e4c1c03380b6a187b))
* **addons:** add local-path-provisioner ([d51eec6](https://github.com/RocketPadPlatforms/talos-terraform/commit/d51eec6f41a916f548370bae9d6361546077a782))
* **ci:** add ci pipeline ([826ae1e](https://github.com/RocketPadPlatforms/talos-terraform/commit/826ae1ef87fce050c4ce5adfa85d5ee855d38061))
* **cilium:** add optional cilium cni ([f519e55](https://github.com/RocketPadPlatforms/talos-terraform/commit/f519e55747e13011f14e78bb9010a1e60a7aba14))
* **configpatches:** Allow configuring config patches for workers ([bf0524a](https://github.com/RocketPadPlatforms/talos-terraform/commit/bf0524a6e05950d0c59cdcdacb49c3b9950d581b))
* **nix:** add flake ([150e0d1](https://github.com/RocketPadPlatforms/talos-terraform/commit/150e0d181d07527b41d2022bf11bcacd927b4f1c))
* **outputs:** Add K8s client config ([f2d6c38](https://github.com/RocketPadPlatforms/talos-terraform/commit/f2d6c389ec730a6b65761757ceb677e8d94a3b31))
* **outputs:** add talos_machine_secrets ([892ae13](https://github.com/RocketPadPlatforms/talos-terraform/commit/892ae13846554ec4c5d0b2118efa3ac199ef90d5))
* replace GitLab CI with GitHub Actions CI and release-please ([f1ef308](https://github.com/RocketPadPlatforms/talos-terraform/commit/f1ef3081ea6e11998ba2dd7b3f12d42e687c8cb0))
* **talos:** add disk selector ([ff648ed](https://github.com/RocketPadPlatforms/talos-terraform/commit/ff648ed36077e2453c8ba02bc177ce402edaf430))
* **talos:** add nodes to client config ([b0bdbb7](https://github.com/RocketPadPlatforms/talos-terraform/commit/b0bdbb7d9d4209603e9caa56883f0d33e5075992))
* **talos:** add option to set installer image ([de4cbe1](https://github.com/RocketPadPlatforms/talos-terraform/commit/de4cbe1c4e5aef455d7dbefc9e4b21608285b5c1))
* **talos:** add patches to nodes ([fa566b6](https://github.com/RocketPadPlatforms/talos-terraform/commit/fa566b6a588daa8c07d9c461fc8a1d668d1498de))
* **talos:** add per-group disk encryption ([d00fdd9](https://github.com/RocketPadPlatforms/talos-terraform/commit/d00fdd94855016a6317bd3ad454fd6c2465bcc7e))
* **talos:** add sleep to wait for k8s api ([fb9a332](https://github.com/RocketPadPlatforms/talos-terraform/commit/fb9a332cf9bcf43d045461f354f96bc8c9de5858))
* **talos:** allow disabling the cluster health check ([db31891](https://github.com/RocketPadPlatforms/talos-terraform/commit/db31891cee83d69dfcd4eddd040ca5167ad13779))
* **talos:** emit Talos 1.14 config documents ([f3fb883](https://github.com/RocketPadPlatforms/talos-terraform/commit/f3fb883d247b81d059193b64842f81fa56b8518d))
* **talos:** make k8s version configurable ([e043cb8](https://github.com/RocketPadPlatforms/talos-terraform/commit/e043cb844f863025d7c48bb53c6157fb3abfaddb))
* **talos:** make talos version configurable ([c7a4153](https://github.com/RocketPadPlatforms/talos-terraform/commit/c7a41539aef633ed8e45f4ff22699e6f4ee6f023))
* **talos:** output manifest sync command ([88d7e93](https://github.com/RocketPadPlatforms/talos-terraform/commit/88d7e93f7986c2889c1c5a7e3aed7ca0a7867408))
* **talos:** reset nodes using destroy command ([6c36412](https://github.com/RocketPadPlatforms/talos-terraform/commit/6c364120b8f8a187d2a00554f57126943b5944c6))


### Bug Fixes

* **addons:** pin local-path helper image ([a891c80](https://github.com/RocketPadPlatforms/talos-terraform/commit/a891c802b8ba27f1137af978c8f4dd945f355253))
* **addons:** treat null addons and cni as defaults ([d0887e2](https://github.com/RocketPadPlatforms/talos-terraform/commit/d0887e22b30b1cc35c14bc5ad82cfe694caf94ea))
* **disk:** fix deletion when using disk selector ([7050542](https://github.com/RocketPadPlatforms/talos-terraform/commit/7050542e0b94e9548149774f62e844226727b8cc))
* Fix input variable name ([7b46276](https://github.com/RocketPadPlatforms/talos-terraform/commit/7b4627653281f4e8ad6eb519d8a0e78bed64fe06))
* Fix list ([5f3b52c](https://github.com/RocketPadPlatforms/talos-terraform/commit/5f3b52ca25743d874f7860927fb584ad3229f397))
* issue with hostname duplicate in talos 1.12 ([17a1a7f](https://github.com/RocketPadPlatforms/talos-terraform/commit/17a1a7f22352e6ea85bf606fca3fd41047562538))
* Remove provider config ([f7a9c02](https://github.com/RocketPadPlatforms/talos-terraform/commit/f7a9c023d2baa7617fe303db33d6761ee9f9411e))
* **talos:** add endpoint to api server cert SANs ([df6a3aa](https://github.com/RocketPadPlatforms/talos-terraform/commit/df6a3aa187011c59797b7ef080773b2cb47e56c7))
* **talos:** add node ip address to cert sans ([34f8d52](https://github.com/RocketPadPlatforms/talos-terraform/commit/34f8d52680ec11d7384b8a08744060bf47b54390))
* **talos:** add talos version to secrets ([094e0f8](https://github.com/RocketPadPlatforms/talos-terraform/commit/094e0f8b545795785a25b9e4c267d641eb6d2843))
* **talos:** bootstrap against a real control plane node ([8ebcd67](https://github.com/RocketPadPlatforms/talos-terraform/commit/8ebcd67738214a4afb7ac0cc7dfcd5ace908807e))
* **talos:** fix control plane ip addresses ([aea6179](https://github.com/RocketPadPlatforms/talos-terraform/commit/aea617948c2fe7da7235a6946a6ec28a7dd1dd55))
* **talos:** fix hostname generation for cp ([286f562](https://github.com/RocketPadPlatforms/talos-terraform/commit/286f5626cf622fd91bec40131eff33bff21858dd))
* **talos:** fix migration of kubeconfig type ([ceb8dc8](https://github.com/RocketPadPlatforms/talos-terraform/commit/ceb8dc8231b58d8b441237e4dc59ca6d302e78d2))
* **talos:** force cluster reset on destroy ([c679fe4](https://github.com/RocketPadPlatforms/talos-terraform/commit/c679fe4f65d39d5fc4779ce6b89dcd6f1cb3f3d4))
* **talos:** poll cluster health instead of fixed sleep ([9dd372c](https://github.com/RocketPadPlatforms/talos-terraform/commit/9dd372c88ab22c5a22eb3939fbeea15340e55806))
* **terraform:** Remove deprecated argument ([de4a11b](https://github.com/RocketPadPlatforms/talos-terraform/commit/de4a11b0bcdb01aefa834c2c69024f4e25d0b9e5))
* **variables:** add input validation and fix typo ([0181c86](https://github.com/RocketPadPlatforms/talos-terraform/commit/0181c8698a20fd9a0154253e54784885c0c016a5))
* **variables:** allow v-prefixed kubernetes_version ([b7d6dd1](https://github.com/RocketPadPlatforms/talos-terraform/commit/b7d6dd1a8925e0d9d7ee6e182a7a8705ed597843))
* **variables:** remove default versions ([d9f8f40](https://github.com/RocketPadPlatforms/talos-terraform/commit/d9f8f401f427f056aa09683d6573a2cabad542c9))
* **variables:** require at least one controlplane ([9f36f08](https://github.com/RocketPadPlatforms/talos-terraform/commit/9f36f08020ceb2b9ef1e1d410a08acc1046dfc59))

## [0.3.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.2.0...v0.3.0) (2026-09-10)


### Features

* **talos:** allow disabling the cluster health check ([db31891](https://github.com/RocketPadPlatforms/talos-terraform/commit/db31891cee83d69dfcd4eddd040ca5167ad13779))

## [0.2.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.1.18...v0.2.0) (2026-09-08)


### Features

* replace GitLab CI with GitHub Actions CI and release-please ([f1ef308](https://github.com/RocketPadPlatforms/talos-terraform/commit/f1ef3081ea6e11998ba2dd7b3f12d42e687c8cb0))
