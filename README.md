# Goods Price Comparison — Deployer

Service-specific CI/CD pipeline definitions for building and deploying the [goods-price-comparison-service](https://github.com/RizkiRachman/goods-price-comparison-service). Integrates with the shared [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) Tekton server.

## Architecture

```
dev-infrastructure (shared)                    this repo (deployer)
─────────────────────────                      ──────────────────────────────────
k3d cluster + registry                         terraform/          Vault → K8s secrets
Tekton Pipelines/Dashboard                     tasks/              Tekton task definitions
Namespace, SA, ClusterRole, registry secret    pipelines/          Pipeline + PipelineRun template
Vault (local/infrastructure)                   pvc/                Workspace + Maven cache
                                               k8s-setup/          Scoped RBAC
                                               scripts/            init / apply / plan / destroy
```

The shared infrastructure is managed by `dev-infrastructure`. This deployer registers service-specific resources (tasks, pipeline, PVCs, secrets) into the shared `tekton-pipelines` namespace. All builds run **in-cluster via Tekton** — no local Maven or Docker required.

## Directory Structure

```
├── .env.template              # Environment variables template
├── k8s-setup/                 # RBAC for scoped service permissions
│   ├── rbac-role.yaml         #   Role: scoped to service resources only
│   └── rbac-rolebinding.yaml  #   RoleBinding: binds RBAC_USER to Role
├── tasks/                     # Tekton task definitions
│   ├── cleanup.yaml           #   Workspace cleanup before build
│   ├── maven-build.yaml       #   Maven compile + package (skip tests)
│   ├── maven-test.yaml        #   Maven test/verify
│   ├── docker-build.yaml      #   Kaniko build + push to registry
│   └── deploy.yaml            #   kubectl deploy to cluster
├── pipelines/                 # Tekton pipeline definitions
│   ├── pipeline.yaml          #   Pipeline with pipeline-mode (full/plan)
│   └── pipeline-run.yaml      #   PipelineRun template
├── pvc/                       # Persistent Volume Claims
│   ├── workspace-pvc.yaml     #   2Gi workspace PVC
│   └── maven-cache-pvc.yaml   #   5Gi Maven cache PVC
├── terraform/                 # Vault → K8s secrets (see terraform/README.md)
│   ├── main.tf                #   Orchestrator: providers + module wiring
│   ├── variables.tf           #   Root-level input variables
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vault-data/        #   Reads secrets from Vault
│       └── k8s-secrets/       #   Creates K8s secrets
└── scripts/
    ├── lib/common.sh          #   Shared: logging, spinner, timer, env, checks
    ├── stages/
    │   ├── init-infra.sh      #   Terraform init + Vault check
    │   └── pipeline-run.sh    #   Trigger Tekton PipelineRun + wait
    ├── init.sh                #   One-time: health check → terraform → K8s resources
    ├── apply.sh               #   Full pipeline: clone → build → test → image → deploy
    ├── plan.sh                #   Partial pipeline: clone → build → test (no deploy)
    └── destroy.sh             #   Teardown: delete all service resources
```

## Quick Start

### 1. Start dev-infrastructure

```bash
cd ../dev-infrastructure
./scripts/init.sh
```

### 2. Configure environment

```bash
cp .env.template .env
# Edit .env if needed (defaults should work for local dev)
```

### 3. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set vault_token
```

### 4. Initialize infrastructure (one-time)

```bash
./scripts/init.sh
```

This registers all service resources: Tekton tasks, pipeline, PVCs, RBAC, and K8s secrets from Vault.

### 5. Run the pipeline

```bash
./scripts/apply.sh    # Full: clone → build → test → image → deploy
./scripts/plan.sh     # Partial: clone → build → test only
```

## Actions

| Action | What it does | When to use |
|--------|-------------|-------------|
| `init.sh` | Health check → Terraform apply (Vault→secrets) → K8s resources (RBAC, PVCs, tasks, pipeline) | Once, or when task/pipeline definitions change |
| `apply.sh` | Triggers Tekton PipelineRun in `full` mode (all tasks including deploy) | Every code change |
| `plan.sh` | Triggers Tekton PipelineRun in `plan` mode (build + test only, no image/deploy) | Verify code compiles and tests pass |
| `destroy.sh` | Deletes deployment, PipelineRuns, tasks, pipeline, PVCs, RBAC, Terraform secrets | Full teardown |

## Pipeline Modes

The `pipeline.yaml` supports a `pipeline-mode` parameter that controls which tasks execute:

| Mode | Tasks executed | Tasks skipped |
|------|---------------|---------------|
| `full` (apply) | cleanup → clone → build → test → build-image → deploy | — |
| `plan` (plan) | cleanup → clone → build → test | build-image, deploy |

Tasks are skipped via Tekton `when` expressions — no separate pipeline definition needed.

## Credential Management

Credentials flow **Vault → Terraform → K8s Secrets**. No `kubectl create secret` anywhere.

```
Vault (local/infrastructure/github)  ──►  Terraform apply  ──►  K8s Secrets
  GITHUB_USERNAME, GITHUB_TOKEN                                      github-maven-credentials
                                                                     maven-settings-secret
```

- **Vault** stores the source of truth (managed by dev-infrastructure)
- **Terraform** reads Vault and creates K8s secrets declaratively
- **Tekton tasks** reference K8s secrets (no changes to task definitions)

See [terraform/README.md](terraform/README.md) for details.

## RBAC Scoping

The `k8s-setup/` directory defines a scoped `Role` + `RoleBinding`:

| Allowed | Blocked (shared infra) |
|---------|----------------------|
| Tasks, TaskRuns, Pipelines, PipelineRuns | ServiceAccount `tekton-sa` |
| PVCs (workspace, maven-cache) | ClusterRole `tekton-sa-role` |
| Secrets (`github-maven-credentials`, `maven-settings-secret`) | ClusterRoleBinding `tekton-sa-binding` |
| Pods, Pods/log (read-only) | Secret `registry-credentials` |
| Deployments, ReplicaSets | |
| ConfigMaps (read-only) | |

## Prerequisites

- [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) running with k3d cluster, Tekton, and Vault
- `kubectl` configured to use the dev-infra cluster context
- `terraform` >= 1.0 installed
- Vault seeded with GitHub credentials at `local/infrastructure/github`

## Troubleshooting

```bash
# Check PipelineRun status
kubectl get pipelineruns -n tekton-pipelines

# View PipelineRun logs
tkn pipelinerun logs -f -n tekton-pipelines <pipeline-run-name>

# Check pod logs
kubectl logs -n tekton-pipelines -l tekton.dev/pipelineRun=<run-name> --all-containers
```
