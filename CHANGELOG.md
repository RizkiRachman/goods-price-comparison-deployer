# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Security scanning tasks: SAST (Static Application Security Testing) and DAST (Dynamic Application Security Testing)
- Gravitee API registration task for automatic API gateway configuration
- New pipeline templates: `pipeline-init.yaml`, `pipeline-plan-apply.yaml`, `pipeline-security.yaml`, `pipeline-security-run.yaml`
- New Terraform modules: `k8s-maven-credentials` and `k8s-vault-token` (replaces monolithic `k8s-secrets`)
- New helper scripts: `scripts/lib/k8s.sh`, `scripts/lib/vault.sh`, `scripts/security.sh`
- Kubernetes deployment and service templates in `templates/` directory
- Host proxy services configuration for Gravitee (`k8s-setup/host-services-gravitee.yaml`)
- Storage and RBAC configuration reorganized into subdirectories

### Changed
- **BREAKING**: Reorganized all Tekton tasks into categorized subdirectories:
  - `tasks/build/` - cleanup, maven-build, maven-test, sast-scan
  - `tasks/database/` - db-migrate, db-provision
  - `tasks/deploy/` - config-apply, dast-scan, deploy, gravitee-register
  - `tasks/image/` - docker-build
- Updated default `MIGRATIONS_PATH` from `src/main/resources/db/migration` to `db/migration`
- Refactored `scripts/lib/common.sh` with improved logging and utility functions
- Enhanced `scripts/stages/pipeline-run.sh` with better error handling
- Updated `.env.template` with new environment variables for Gravitee and security scanning
- Restructured `k8s-setup/` with organized rbac/ and storage/ subdirectories

### Removed
- **BREAKING**: Removed old flat task files (cleanup.yaml, db-migrate.yaml, db-provision.yaml, deploy.yaml, docker-build.yaml, maven-build.yaml, maven-test.yaml)
- **BREAKING**: Removed old pipeline files (pipeline.yaml, pipeline-run.yaml)
- **BREAKING**: Removed old rbac files (rbac-role.yaml, rbac-rolebinding.yaml)
- **BREAKING**: Removed old PVC files (maven-cache-pvc.yaml, workspace-pvc.yaml)
- **BREAKING**: Removed `scripts/plan.sh` (functionality merged into new pipeline structure)
- **BREAKING**: Removed `terraform/modules/k8s-secrets/` (replaced by modular approach)

### Security
- Added SAST scanning capability for early vulnerability detection in source code
- Added DAST scanning capability for runtime security testing
- Improved secret management with dedicated Vault token module

## [1.0.0] - 2024-04-13

### Added
- Initial release of goods-price-comparison-deployer
- Tekton pipeline definitions for CI/CD
- Terraform configuration for Vault to K8s secrets
- Support for in-cluster builds via Kaniko
- Database provisioning and migration tasks
- Deployment automation with kubectl
- RBAC configuration for scoped permissions
- Host connectivity services for Vault and PostgreSQL

[Unreleased]: https://github.com/RizkiRachman/goods-price-comparison-deployer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/RizkiRachman/goods-price-comparison-deployer/releases/tag/v1.0.0
