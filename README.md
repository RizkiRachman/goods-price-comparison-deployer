# Tekton Deployment Setup

This directory contains service-specific Tekton pipeline and task definitions for building and deploying the goods-price-comparison-service. It integrates with the shared [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) Tekton server.

## Architecture

```
dev-infrastructure (shared)          goods-price-comparison-service (this repo)
─────────────────────────           ───────────────────────────────────────────
k3d cluster + registry              deployer/
Tekton Pipelines/Dashboard/Triggers   ├── tasks/          Service-specific tasks
Namespace, SA, RBAC, registry secret  ├── pipelines/      Pipeline definition
                                      ├── pvc/            Workspace + Maven cache
                                      └── scripts/        Apply/run/status/cleanup
```

The shared infrastructure (k3d cluster, Tekton installation, service account, RBAC, registry secret) is managed by `dev-infrastructure`. This deployer only registers service-specific resources (tasks, pipeline, PVCs, secrets) into the shared `tekton-pipelines` namespace.

## Directory Structure

```
deployer/
├── .env.template          # Environment variables template
├── k8s-setup/              # RBAC for scoped service permissions
│   ├── rbac-role.yaml      # Role: scoped to service resources only
│   └── rbac-rolebinding.yaml # RoleBinding: binds RBAC_USER to Role
├── tasks/                 # Tekton task definitions
│   ├── cleanup.yaml       # Workspace cleanup before build
│   ├── maven-build.yaml   # Maven compile + package (skip tests)
│   ├── maven-test.yaml    # Maven test/verify
│   ├── docker-build.yaml  # Kaniko build + push to registry
│   └── deploy.yaml        # kubectl deploy to cluster
├── pipelines/             # Tekton pipeline definitions
│   ├── pipeline.yaml      # Pipeline: cleanup→clone→build→test→image→deploy
│   └── pipeline-run.yaml  # PipelineRun template (generateName)
├── pvc/                   # Persistent Volume Claims
│   ├── workspace-pvc.yaml # 2Gi workspace PVC
│   └── maven-cache-pvc.yaml # 5Gi Maven cache PVC
└── scripts/               # Helper scripts
    ├── apply.sh           # Apply service resources to shared cluster
    ├── run-pipeline.sh    # Trigger a new PipelineRun
    ├── status.sh          # Check status of service Tekton resources
    ├── cleanup.sh         # Remove service resources (keeps shared infra)
    └── create-maven-settings-secret.sh  # Create maven settings secret
```

## Quick Start

1. **Start dev-infrastructure** (if not already running)
   ```bash
   cd ../dev-infrastructure
   ./scripts/init.sh  # Option 7: Setup All
   ./services/tekton/scripts/start.sh
   ```

2. **Configure environment variables**
   ```bash
   cp .env.template .env
   # Edit .env — set GITHUB_USERNAME and GITHUB_TOKEN for GitHub Packages
   ```

3. **Apply service resources**
   ```bash
   ./scripts/apply.sh
   ```

4. **Run the pipeline**
   ```bash
   ./scripts/run-pipeline.sh
   ```

5. **Check status**
   ```bash
   ./scripts/status.sh
   ```

## RBAC Scoping

The `k8s-setup/` directory defines a scoped `Role` + `RoleBinding` that limits what this service can do in the shared `tekton-pipelines` namespace:

| Allowed | Blocked (shared infra) |
|---------|----------------------|
| Tasks, TaskRuns, Pipelines, PipelineRuns | ServiceAccount `tekton-sa` |
| PVCs (workspace, maven-cache) | ClusterRole `tekton-sa-role` |
| Secrets (`github-maven-credentials`, `maven-settings-secret`) | ClusterRoleBinding `tekton-sa-binding` |
| Pods, Pods/log (read-only) | Secret `registry-credentials` |
| Deployments, ReplicaSets | Secret `gcr-key` |
| ConfigMaps (read-only) | |

The `RBAC_USER` in `.env` identifies this service in the RoleBinding. This follows the dev-infrastructure pattern where each component gets its own scoped identity.

## Environment Variables

Service-specific configuration in `.env`:

- `RBAC_USER` - Service identity for RBAC RoleBinding (default: `goods-price-service`)
- `GITHUB_USERNAME` - GitHub username for Maven Packages access
- `GITHUB_TOKEN` - GitHub token for Maven Packages access

All other values (namespace, registry host, image names) are hardcoded in the YAML files and aligned with dev-infrastructure defaults.

## Pipeline Flow

The `goods-price-pipeline` executes:

1. **cleanup** - Clean workspace from previous builds
2. **git-clone** - Clone source code (from Tekton catalog)
3. **maven-build** - Build with Maven (skip tests)
4. **maven-test** - Run Maven tests
5. **docker-build** - Build and push Docker image using Kaniko
6. **deploy** - Deploy to Kubernetes

## Scripts

- `apply.sh` - Apply service tasks, pipeline, PVCs, and secrets to the shared cluster
- `run-pipeline.sh` - Trigger a new PipelineRun
- `status.sh` - Check status of Tekton resources
- `cleanup.sh` - Remove service-specific resources (does NOT touch shared infrastructure)

## Prerequisites

- [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) running with k3d cluster and Tekton installed
- kubectl configured to use the dev-infra cluster context
- GitHub credentials for Maven Packages (optional, if using private packages)

## Troubleshooting

Check PipelineRun status:
```bash
kubectl get pipelineruns -n tekton-pipelines
```

View PipelineRun logs:
```bash
tkn pipelinerun logs -f -n tekton-pipelines <pipeline-run-name>
```

Check pod logs:
```bash
kubectl logs -n tekton-pipelines -l tekton.dev/pipelineRun=<run-name> --all-containers
```
