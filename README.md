# Goods Price Comparison — Deployer

Service-specific CI/CD pipeline definitions for building and deploying the [goods-price-comparison-service](https://github.com/RizkiRachman/goods-price-comparison-service). Integrates with the shared [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) Tekton server.

## Architecture

```
dev-infrastructure (shared)                    this repo (deployer)
─────────────────────────                      ──────────────────────────────────
k3d cluster + registry                         terraform/          Vault → K8s secrets
Tekton Pipelines/Dashboard                     tasks/              Tekton task definitions
Namespace, SA, ClusterRole, registry secret    pipelines/          Pipeline + PipelineRun template
Vault + PostgreSQL (on host)                   pvc/                Workspace + Maven cache
                                               k8s-setup/          Scoped RBAC
                                               scripts/            init / apply / plan / destroy
```

The shared infrastructure is managed by `dev-infrastructure`. This deployer registers service-specific resources (tasks, pipeline, PVCs, secrets) into the shared `tekton-pipelines` namespace. All builds run **in-cluster via Tekton** — no local Maven or Docker required.

## Quick Start

```bash
# 1. Start dev-infrastructure
cd ../dev-infrastructure && ./scripts/init.sh

# 2. Configure this repo
cp .env.template .env            # Edit .env if needed (defaults work for local dev)
cd terraform
cp terraform.tfvars.example terraform.tfvars  # Set vault_token
cd ..

# 3. Create host-proxy services (Vault + PostgreSQL access from pods)
#    Replace 192.168.x.x with your host IP (from ifconfig)
HOST_IP=192.168.18.195

kubectl apply -n tekton-pipelines -f - <<EOF
apiVersion: v1
kind: Service
metadata: {name: vault-host}
spec: {clusterIP: None, ports: [{port: 8201, targetPort: 8201}]}
EOF

printf '{"apiVersion":"v1","kind":"Endpoints","metadata":{"name":"vault-host"},"subsets":[{"addresses":[{"ip":"%s"}],"ports":[{"port":8201}]}]}' \
  "$HOST_IP" | kubectl apply -n tekton-pipelines -f -

kubectl apply -n tekton-pipelines -f - <<EOF
apiVersion: v1
kind: Service
metadata: {name: postgres-host}
spec: {clusterIP: None, ports: [{port: 5432, targetPort: 5432}]}
EOF

printf '{"apiVersion":"v1","kind":"Endpoints","metadata":{"name":"postgres-host"},"subsets":[{"addresses":[{"ip":"%s"}],"ports":[{"port":5432}]}]}' \
  "$HOST_IP" | kubectl apply -n tekton-pipelines -f -

# 4. Initialize (one-time, or when task/pipeline definitions change)
./scripts/init.sh

# 5. Run the pipeline
./scripts/apply.sh    # Full: clone → build → test → image → db-provision → db-migrate → deploy
./scripts/plan.sh     # Partial: clone → build → test only
```

## Pipeline Flow

```
cleanup → clone → build → test → build-image → db-provision → db-migrate → deploy
                                     ────────────   ────────────
                                     (full mode)    (full mode)
```

| Mode | Tasks executed | Skipped |
|------|---------------|---------|
| `full` (apply) | all tasks | — |
| `plan` (plan) | cleanup → clone → build → test | build-image, db-provision, db-migrate, deploy |

Tasks are skipped via Tekton `when` expressions — no separate pipeline definition needed.

## Scripts

| Script | What it does | When to use |
|--------|-------------|-------------|
| `init.sh` | Health check → Terraform apply → K8s resources (RBAC, PVCs, tasks, pipeline) | Once, or when YAML definitions change |
| `apply.sh` | Full pipeline run | Every code change |
| `plan.sh` | Build + test only | Verify code compiles and tests pass |
| `destroy.sh` | Delete all service resources | Full teardown |
| `clean.sh` | Delete PipelineRuns/TaskRuns | Free disk or clean failed runs |

### clean.sh options

```bash
./scripts/clean.sh                  # Interactive: choose what to clean
./scripts/clean.sh --failed         # Delete only failed runs
./scripts/clean.sh --all            # Delete all runs
./scripts/clean.sh --older-than 7   # Delete runs older than 7 days
./scripts/clean.sh --all --yes      # Skip confirmation
```

## Host Connectivity

Vault and PostgreSQL run on the **host machine** (outside the k3d cluster). Pipeline pods need `vault-host` and `postgres-host` Services with manual Endpoints to reach them.

> **Important**: `host.k3d.internal` does NOT resolve from within pods. Use the Service+Endpoint approach instead.

The Services must be in the **same namespace as Tekton pods** (`tekton-pipelines`), otherwise DNS won't resolve.

```bash
# Verify connectivity from inside the cluster
kubectl run -n tekton-pipelines test-vault --image=curlimages/curl -it --rm -- \
  curl -s http://vault-host:8201/v1/sys/health
```

## Database Provisioning

The `db-provision` task automatically:
1. Verifies Vault connectivity and token validity
2. Reads infrastructure DB credentials from Vault (`local/infrastructure/data/database`)
3. Checks if component credentials already exist (skips if valid, re-provisions if password is empty)
4. Generates a random 32-char password (Alpine-compatible)
5. Creates/updates the database and user in PostgreSQL
6. Pushes credentials to Vault (`local/component/<service-name>`)

Passwords are masked in logs: `6e****ae (32 chars)`.

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

## Environment Variables

All pipeline/task defaults come from `.env`. No hardcoded values in YAML — every param uses `${VAR}` with envsubst. Fallback defaults are in `scripts/lib/common.sh`.

| Variable | Description | Default |
|----------|-------------|---------|
| `PIPELINE_NAMESPACE` | Namespace for pipeline resources | `tekton-pipelines` |
| `RBAC_USER` | RBAC identity | `goods-price-service` |
| `GIT_REPO_URL` | Service repository URL | `https://github.com/RizkiRachman/goods-price-comparison-service.git` |
| `GIT_REPO_DEFAULT_BRANCH` | Git branch | `main` |
| `REGISTRY_CLUSTER_HOST` | In-cluster registry host | `k3d-dev-infra-registry` |
| `REGISTRY_CLUSTER_PORT` | In-cluster registry port | `5000` |
| `REGISTRY_PORT` | Host registry port | `5002` |
| `IMAGE_NAME` | Container image name | `goods-price-comparison-service` |
| `IMAGE_TAG` | Image tag | `latest` |
| `DEPLOYMENT_NAMESPACE` | Deployment namespace | `tekton-pipelines` |
| `DEPLOYMENT_NAME` | Deployment name | `goods-price-service` |
| `DEPLOYMENT_PORT` | Container port | `8080` |
| `VAULT_ADDRESS_TERRAFORM` | Vault URL for Terraform (host) | `http://localhost:8201` |
| `VAULT_ADDRESS_PIPELINE` | Vault URL for pipeline tasks (in-cluster) | `http://vault-host:8201` |
| `VAULT_TOKEN` | Vault root token | — |
| `INFRA_DB_MOUNT` | Vault path for infra DB credentials | `local/infrastructure` |
| `COMPONENT_MOUNT` | Vault path for component credentials | `local/component` |
| `POSTGRES_HOST` | PostgreSQL host (in-cluster DNS) | `postgres-host` |
| `POSTGRES_PORT` | PostgreSQL port | `5432` |
| `MIGRATIONS_PATH` | Flyway migrations directory | `src/main/resources/db/migration` |
| `COMPONENT_NAME` | Component name for Vault path | defaults to `DEPLOYMENT_NAME` |
| `KUBECTL_IMAGE` | kubectl container image | `bitnami/kubectl:latest` |
| `MAVEN_IMAGE` | Maven container image | `maven:3.9-eclipse-temurin-17` |
| `KANIKO_IMAGE` | Kaniko container image | `gcr.io/kaniko-project/executor:latest` |

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
│   ├── db-provision.yaml      #   Create DB, user, push credentials to Vault
│   ├── db-migrate.yaml        #   Flyway migrate + verify
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
    ├── destroy.sh             #   Teardown: delete all service resources
    └── clean.sh               #   Delete PipelineRuns/TaskRuns
```

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
- Vault seeded with database credentials at `local/infrastructure/database`
- `vault-host` and `postgres-host` Services+Endpoints in `tekton-pipelines` namespace

## Troubleshooting

```bash
# Check PipelineRun status
kubectl get pipelineruns -n tekton-pipelines

# View task logs
kubectl logs -n tekton-pipelines <task-pod-name> -c step-<step-name>

# View all logs for a run
kubectl logs -n tekton-pipelines -l tekton.dev/pipelineRun=<run-name> --all-containers

# Test Vault connectivity from cluster
kubectl run -n tekton-pipelines test-vault --image=curlimages/curl -it --rm -- \
  curl -s http://vault-host:8201/v1/sys/health

# Test PostgreSQL connectivity from cluster
kubectl run -n tekton-pipelines test-pg --image=postgres:15-alpine -it --rm -- \
  psql -h postgres-host -U dev_infrastructure -d postgres

# Clean up failed PipelineRuns
./scripts/clean.sh --failed
```
