# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Caddy reverse proxy** — serves dashboard static files (`dist/`) and proxies `/v1/*`, `/v2/*` to backend on `localhost:8080`. Backend is never directly exposed.
- **Cloudflare Tunnel** — routes `aneh.biz.id` → `localhost:80` (Caddy). No open ports (except SSH 22). TLS terminated at Cloudflare Edge.
- **VPS production deploy task** (`tasks/deploy/vps-deploy.yaml`): SSH-based deployment to production VPS
- **New Terraform module** `k8s-vps-ssh`: Creates K8s secret `vps-ssh-key` from Vault (`local/infrastructure/vps`)
- VPS SSH credential management via Vault → Terraform → K8s Secrets
- Support for `--production` flag in `apply.sh` (VPS SSH deploy mode)
- **Caddy reverse proxy** on `:80` — serves dashboard `dist/` and proxies `/v1/*`, `/v2/*` → backend `:8080`
- **Cloudflare Tunnel** — routes `aneh.biz.id` → `localhost:80` (Caddy); backend never publicly exposed
- **Passwordless sudo** for deploy user — expanded to manage Caddy + cloudflared
- **`docs/vps-setup-guide.md`** — comprehensive VPS setup guide (SSH → systemd → Caddy → Tunnel → CI/CD)

### Changed
- **Project structure refactored** — consolidated into `components/`:
  - `components/tekton/` — tasks + pipelines
  - `components/kubernetes/` — RBAC, storage, services, deployment templates
  - `components/vps/` — Caddy, Cloudflare, service management scripts
  - `components/terraform/` — Vault → K8s secrets
- **Renamed for clarity**:
  - `installation/init.sh` → `register-resources.sh`
  - `installation/vps.sh` → `setup-vps.sh`
  - `installation/setup/01-vps.sh` → `01-users.sh`
  - `installation/setup/03-clone.sh` → `03-clone-repos.sh`
  - `installation/setup/04-service.sh` → `04-systemd.sh`
  - `scripts/clean.sh` → `clean-runs.sh`
  - `components/tekton/pipelines/*` → flattened naming (`pipeline.yaml`, `pipeline-run.yaml`, `security-pipeline.yaml`, `security-run.yaml`)
  - `components/vps/caddy/manage.sh` → `control.sh`
  - `helpers/be-tunnel.sh` → `port-forward.sh`
- **`sumopod` → `vps`** naming — all SSH host aliases, ops scripts, and docs references updated
- **All internal source paths and doc links updated** — consistent with new structure
- **README.md** — architecture diagram updated with Caddy + Tunnel flow; directory tree and script tables refreshed
- **AGENTS.md** — architecture, directory tree, and production VPS section synced with current setup

### Changed
- **Performance: Docker build optimized from ~5min to ~12s** — Reverted service repo Dockerfile from multi-stage (Maven build inside Docker) to simple JRE runtime. The `maven-build` Tekton task pre-compiles the JAR, so the Dockerfile just `COPY target/*.jar` from the workspace. This eliminates redundant Maven compilation inside Docker.
- **`tasks/image/docker-build.yaml`**: Removed `GH_PACKAGES_USERNAME` / `GH_PACKAGES_TOKEN` env vars and `--build-arg` flags — no longer needed since the Dockerfile doesn't run Maven.
- **Kaniko `--build-arg` syntax fix**: Changed from `--build-arg=VAR` (single arg with `=`) to separate `--build-arg` / `VAR` (two args). The former syntax was not resolving environment variable values correctly.
- **Kaniko cache management**: Temporarily disabled `--cache=true` to clear stale cached layers from failed builds, then re-enabled it. Added note in AGENTS.md about cache invalidation when build-args change.
- **Terraform re-applied**: Refreshed `github-maven-credentials` and `maven-settings-secret` K8s secrets from Vault after GitHub token rotation.

### Removed
- `apply.sh`: Replaced `--cloud` mode with `--production` mode; removed GHCR references
- `apply-production.sh`: Simplified to a thin wrapper around `apply.sh --production`
- Pipeline (`pipeline-init.yaml`): Added conditional `vps-deploy` task for production mode; `deploy` now only runs in local mode; removed GHCR params
- Pipeline Run template: Removed `ghcr-owner` param, added `maven-settings-path`
- `scripts/lib/k8s.sh`: Removed GHCR_OWNER from envsubst vars, added MAVEN_SETTINGS_PATH
- `scripts/lib/common.sh`: Removed GHCR_OWNER default; registry health check skipped for production mode
- `scripts/lib/vault.sh`: Added `vps` to `check_vault_secrets` loop
- `scripts/stages/pipeline-run.sh`: Removed `stage_production_pipeline_run` function (no longer needed)
- `.env.template`: Added VPS config vars (`VPS_SSH_USER`, `VPS_SSH_HOST`, `MAVEN_SETTINGS_PATH`); removed GHCR variables
- Documentation: Updated AGENTS.md, README.md with production mode flow

### Removed
- Cloud/GHCR mode (`--cloud` flag, GHCR_OWNER references)
- `pipelines/pipeline-plan-apply-production.yaml` (no longer needed — single pipeline handles all modes)

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
