# Changelog

## [1.0.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.3.0...v1.0.0) (2026-11-10)


### ⚠ BREAKING CHANGES

* **talos:** node_data is replaced by node_groups, config_patches_* by config_patches, install_disk/install_disk_selector/install_image by node_groups image specs and install_disk_match. Provider >= 0.12.0 and talos_version >= v1.14 are now required. See README upgrade guide.

### Features

* **talos:** emit Talos 1.14 config documents ([f3fb883](https://github.com/RocketPadPlatforms/talos-terraform/commit/f3fb883d247b81d059193b64842f81fa56b8518d))

## [0.3.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.2.0...v0.3.0) (2026-09-10)


### Features

* **talos:** allow disabling the cluster health check ([db31891](https://github.com/RocketPadPlatforms/talos-terraform/commit/db31891cee83d69dfcd4eddd040ca5167ad13779))

## [0.2.0](https://github.com/RocketPadPlatforms/talos-terraform/compare/v0.1.18...v0.2.0) (2026-09-08)


### Features

* replace GitLab CI with GitHub Actions CI and release-please ([f1ef308](https://github.com/RocketPadPlatforms/talos-terraform/commit/f1ef3081ea6e11998ba2dd7b3f12d42e687c8cb0))
