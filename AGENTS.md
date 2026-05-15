# Goods Price Comparison — Deployer

Service-specific CI/CD pipeline definitions for building and deploying the [goods-price-comparison-service](https://github.com/RizkiRachman/goods-price-comparison-service). Integrates with the shared [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) Tekton server.

## Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                           HOST MACHINE                                      │
│                    (dev-infrastructure Docker)                               │
│                                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────────┐  │
│  │  Vault   │    │PostgreSQL│    │ Gravitee │    │  k3d Registry         │  │
│  │ :8201    │    │ :5432    │    │ :8083    │    │  :5000/:5002          │  │
│  │          │    │          │    │          │    │                        │  │
│  │secrets/  │    │  goods_  │    │ APIM GW  │    │  Container images     │  │
│  │infra     │    │  price   │    │          │    │                        │  │
│  └────┬─────┘    └──────────┘    └──────────┘    └────────────────────────┘  │
│       │                                                                      │
│       │              ┌──────────────────────────────────────┐               │
│       │              │        k3d Kubernetes Cluster        │               │
│       │              │                                      │               │
│       │              │  ┌─────────────────────────────────┐ │               │
│       ├──────────────┼──► Tekton Pipeline                  │ │               │
│       │  reads       │  │                                 │ │               │
│       │  via API     │  │  cleanup → clone → build → test │ │               │
│       │              │  │  → image → db → config → deploy │ │               │
│       │              │  │  → gravitee-register            │ │               │
│       │              │  └──────────┬──────────────────────┘ │               │
│       │              │             │                        │               │
│       │              │  ┌──────────▼──────────────────────┐ │               │
│       │              │  │  K8s Resources                   │ │               │
│       │              │  │  ┌──────────┐ ┌───────────────┐ │ │               │
│       │              │  │  │Deployment│ │   Secrets     │ │ │               │
│       │              │  │  │:8080     │ │ github-maven  │ │ │               │
│       │              │  │  │          │ │ vault-token   │ │ │               │
│       │              │  │  │  +PVCs   │ │ vps-ssh-key   │ │ │               │
│       │              │  │  └──────────┘ └───────────────┘ │ │               │
│       │              │  └─────────────────────────────────┘ │               │
│       │              └──────────────────────────────────────┘               │
│       │                                                                      │
│       │              ┌──────────────────────────────────────┐               │
│       └──────────────┼── Terraform (this repo)              │               │
│          reads Vault │                                      │               │
│          → K8s       │  vault-data → k8s-maven-credentials  │               │
│          Secrets     │  vault-data → k8s-vault-token        │               │
│                      │  vault-data → k8s-vps-ssh            │               │
│                      └──────────────────────────────────────┘               │
└──────────────────────────────────────────────────────────────────────────────┘
         │                    │
         │ vps-deploy (SSH)   │ deploy (kubectl)
         ▼                    ▼
┌──────────────────────────────────────────┐  ┌──────────────────────┐
│           PRODUCTION VPS                 │  │  GITHUB              │
│           43.129.38.221                  │  │                      │
│                                          │  │  ┌───────────────┐   │
│  aneh.biz.id ──► Cloudflare Tunnel      │  │  │ Source Repos  │   │
│                     │                    │  │  │ - service     │   │
│                     ▼                    │  │  │ - dashboard   │   │
│               Caddy :80                  │  │  └───────────────┘   │
│                /   \                     │  │                      │
│          FE    /     \    BE             │  │  ┌───────────────┐   │
│   ┌───────────┘       └──────────┐      │  │  │ GitHub        │   │
│   │ Serves dist/          Proxy  │      │  │  │ Packages      │   │
│   │ (dashboard)      /v1/* /v2/* │      │  │  │ (Maven deps)  │   │
│   └──────────────────────────────┘      │  │  └───────────────┘   │
│                                          │  └──────────────────────┘
│  systemd services:                       │
│    goods-price-service       :8080       │
│    goods-price-dashboard     :5173       │
│    caddy                     :80         │
│    cloudflared              (tunnel)     │
│                                          │
│  /home/production/app/                   │
│    goods-price-comparison-service/       │
│    goods-price-comparison-dashboard/     │
│                                          │
└──────────────────────────────────────────┘
```

The shared infrastructure is managed by `dev-infrastructure`. This deployer registers service-specific resources (tasks, pipeline, PVCs, secrets) into the shared `tekton-pipelines` namespace. All builds run **in-cluster via Tekton** — no local Maven or Docker required.

### Credential Flow

```
Vault ──► Terraform ──► K8s Secrets ──► Tekton Tasks

  Vault path                    K8s Secret               Used by
  ─────────────────           ─────────────────       ────────────
  local/infrastructure/github  github-maven-credentials  maven-build
  local/infrastructure/github  maven-settings-secret    maven-build
  local/infrastructure/vps     vps-ssh-key              vps-deploy
  vault_token (env var)        vault-token              db-provision
                                                         db-migrate
                                                         config-apply
                                                         vps-deploy
  local/infrastructure/database  (read at runtime)      db-provision
  local/component/goods-price    (read at runtime)      db-migrate, vps-deploy
  local/infrastructure/gravitee  (read at runtime)      gravitee-register
```

### Pipeline Flow by Mode

```
LOCAL MODE:
  cleanup → clone → build → test → build-image → db-provision → db-migrate → config-apply → deploy → gravitee-register
                                                                                                        (K8s)

PRODUCTION MODE:
  cleanup → clone → build → test → [skip image] → db-provision → db-migrate → config-apply → vps-deploy → gravitee-register
                                                                                                 (SSH → VPS)
```

Two pipeline modes:
- **`local` mode** (default): Builds image with Kaniko, pushes to local k3d registry (`k3d-dev-infra-registry:5000`), deploys to Kubernetes. Old image is cleaned up before push to keep only `latest`.
- **`production` mode** (`--production`): Skips image build and K8s deploy. Runs CI (clone → build → test → db) then SSHs to the production VPS to deploy: git pull → mvn package → flyway:migrate → systemctl restart. SSH key managed by Vault → Terraform → K8s Secret.

## Quick Start

```bash
# 1. Start dev-infrastructure
cd ../dev-infrastructure && ./scripts/init.sh

# 2. Configure this repo
cp .env.template .env            # Edit .env if needed (defaults work for local dev)
cd terraform
cp terraform.tfvars.example terraform.tfvars  # Set vault_token
cd ..

# 3. Create host-proxy services (Vault + PostgreSQL + Gravitee access from pods)
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

kubectl apply -n tekton-pipelines -f - <<EOF
apiVersion: v1
kind: Service
metadata: {name: gravitee-host}
spec: {clusterIP: None, ports: [{port: 8083, targetPort: 8083}]}
EOF

printf '{"apiVersion":"v1","kind":"Endpoints","metadata":{"name":"gravitee-host"},"subsets":[{"addresses":[{"ip":"%s"}],"ports":[{"port":8083}]}]}' \
  "$HOST_IP" | kubectl apply -n tekton-pipelines -f -

# 4. Initialize (one-time, or when task/pipeline definitions change)
./scripts/register-resources.sh

# 5. Run the pipeline
./scripts/apply.sh                  # Local mode (default): build + push to local registry → deploy
./scripts/apply.sh --production     # Production mode: CI + VPS SSH deploy
./scripts/apply-production.sh       # Same as apply.sh --production
./scripts/security.sh               # Security scan: SAST + DAST analysis
```

## Pipeline Flow

```
cleanup → clone → build → test → [build-image*] → db-provision → db-migrate → config-apply → [deploy** | vps-deploy***] → gravitee-register
                                  ─────────────               ────────────                                                         
                                  (*local mode only)          (full mode)                                                          
                                  **deploy (local mode)
                                  ***vps-deploy (production mode)
```

| Mode | Tasks executed | Skipped |
|------|---------------|---------|
| `local` (apply) | all tasks except vps-deploy | vps-deploy |
| `production` (apply --production) | cleanup → clone → build → test → db-provision → db-migrate → config-apply → vps-deploy → gravitee-register | build-image, K8s deploy |
| `security` | cleanup → clone → build → test → sast-scan → build-image → deploy → dast-scan | db-provision, db-migrate, gravitee-register |

Tasks are skipped via Tekton `when` expressions — no separate pipeline definition needed.

### Local Mode

Builds image with Kaniko, pushes to local k3d registry, deploys to Kubernetes. Before Kaniko pushes a new image, the `docker-build` task deletes the old image from the local registry via the Registry API (`DELETE /v2/<name>/manifests/<digest>`). This ensures only the `latest` tag is kept, reducing storage.

#### Image Build Optimization

The service repo Dockerfile is a **simple JRE runtime image** — it does NOT compile the application. The JAR is pre-built by the `maven-build` Tekton task earlier in the pipeline. The Dockerflow:

```
maven-build (compiles JAR → workspace/target/*.jar)
     │
     ▼
docker-build (Kaniko: COPY target/*.jar → image)
```

**Why this matters**: The Dockerfile was previously a multi-stage build that ran Maven inside Docker. Since the `maven-build` task already compiles the JAR, this was redundant — Maven ran twice, adding ~4 minutes to each pipeline run. The fix reduced `build-image` step time from ~5 minutes to ~12 seconds.

#### Kaniko `--build-arg` Considerations

The `docker-build` task does NOT pass GitHub credential build-args (`GH_PACKAGES_USERNAME` / `GH_PACKAGES_TOKEN`) because the Dockerfile is JRE-only and never runs Maven.

If the Dockerfile is changed to require build-args in the future, note these lessons:

1. **Syntax matters**: `--build-arg=VAR` (single arg with `=`) does NOT resolve environment variable values correctly in Kaniko. Use separate args: `--build-arg` `VAR`.
2. **Explicit expansion is most reliable**: Use a script with shell expansion: `--build-arg "VAR=${VAR}"` ensures the value is passed explicitly.
3. **Stale cache invalidation**: Kaniko's `--cache=true` caches layers including build-arg state. If a build fails with wrong args and the cache is persisted, subsequent builds with correct args may still fail because Kaniko reuses the stale cached layer. Remove `--cache=true` temporarily to clear the cache.

### Production Mode

The production pipeline (`apply.sh --production`) runs CI (clone → build → test → db-provision → db-migrate → config-apply) then replaces the K8s deploy step with a **VPS SSH deploy** (`vps-deploy` task). The `vps-deploy` task:

1. SSHs into the VPS using credentials from Vault (`local/infrastructure/vps`) → K8s Secret (`vps-ssh-key`)
2. Verifies git branch is `main`
3. Pulls latest code (`git pull origin main`)
4. Builds with Maven (`mvn clean install -U` + `mvn package -DskipTests`)
5. Reads database credentials from Vault
6. Runs Flyway migrations (`mvn flyway:migrate`)
7. Restarts systemd service (`sudo systemctl restart`)
8. Health check via `curl http://localhost:8080/actuator/health`

Vault data path: `local/infrastructure/vps` with keys `SSH_PRIVATE_KEY`, `SSH_USER`, `SSH_HOST`, `SSH_PORT`.

The `gravitee-register` step runs after both deploy and vps-deploy (whichever was executed).

### Production Architecture (VPS)

On the production VPS, traffic flows through a **Cloudflare Tunnel** → **Caddy** reverse proxy:

```
aneh.biz.id ──► Cloudflare Edge (TLS)
  ──► Cloudflare Tunnel (d847cde0-...)
    ──► VPS cloudflared daemon
      ──► localhost:80 (Caddy)
        ├── /v1/*, /v2/*           ──► proxy ──► localhost:8080 (backend)
        ├── /actuator/health        ──► proxy ──► localhost:8080
        └── /* (dist/ static files) ──► serve ──► dashboard FE
```

Key points:
- **No open ports** except SSH (22) — Tunnel establishes an outbound-only connection to Cloudflare Edge
- **Backend is NEVER exposed publicly** — only reachable via Caddy's internal proxy
- **Caddy serves dashboard directly** from `/home/production/app/goods-price-comparison-dashboard/dist/` (no need for Vite preview to be public)
- **Dashboard JS calls same origin** (`/v1/prices/search`) → Caddy proxies to `localhost:8080`
- **Dashboard systemd service** (`goods-price-comparison-dashboard`) runs `vite preview` on port 5173 for rebuilding, but Caddy is the actual entry point
- See [docs/vps-setup-guide.md](docs/vps-setup-guide.md) §8 (Caddy) and §9 (Cloudflare Tunnel) for full setup details

## Scripts

| Script | What it does | When to use |
|--------|-------------|-------------|
| `register-resources.sh` | Health check → Terraform apply → K8s resources (RBAC, PVCs, tasks, pipeline) | Once, or when YAML definitions change |
| `apply.sh` | Pipeline run. Default `--local` (build + local registry) or `--production` (VPS SSH) | Every code change |
| `apply-production.sh` | Same as `apply.sh --production` | Deploying with VPS SSH deploy |
| `destroy.sh` | Delete all service resources | Full teardown |
| `clean-runs.sh` | Delete PipelineRuns/TaskRuns | Free disk or clean failed runs |
| `security.sh` | Security scan: SAST + DAST analysis | Security validation |

### clean-runs.sh options

```bash
./scripts/clean-runs.sh                  # Interactive: choose what to clean
./scripts/clean-runs.sh --failed         # Delete only failed runs
./scripts/clean-runs.sh --all            # Delete all runs
./scripts/clean-runs.sh --older-than 7   # Delete runs older than 7 days
./scripts/clean-runs.sh --all --yes      # Skip confirmation
```

## Host Connectivity

Vault, PostgreSQL, and Gravitee APIM run on the **host machine** (outside the k3d cluster). Pipeline pods need `vault-host`, `postgres-host`, and `gravitee-host` Services with manual Endpoints to reach them.

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

## Security Scanning

The deployer now includes security scanning capabilities via the `security.sh` script:

### SAST (Static Application Security Testing)
- Runs during the build phase
- Analyzes source code for security vulnerabilities
- Integrated into `security-pipeline.yaml`

### DAST (Dynamic Application Security Testing)
- Runs against deployed application
- Tests runtime security posture
- Requires successful deployment before execution

Run security scan:
```bash
./scripts/security.sh
```

## Credential Management

Credentials flow **Vault → Terraform → K8s Secrets**. No `kubectl create secret` anywhere.

```
Vault (local/infrastructure/github)  ──►  Terraform apply  ──►  K8s Secrets
  GITHUB_USERNAME, GITHUB_TOKEN                                      github-maven-credentials
                                                                     maven-settings-secret

Vault (local/infrastructure/vps)    ──►  Terraform apply  ──►  K8s Secrets
  SSH_PRIVATE_KEY, SSH_USER, SSH_HOST                                 vps-ssh-key
```

- **Vault** stores the source of truth (managed by dev-infrastructure)
- **Terraform** reads Vault and creates K8s secrets declaratively
- **Tekton tasks** reference K8s secrets (no changes to task definitions)

See [components/terraform/README.md](components/terraform/README.md) for details.

## Environment Variables

All pipeline/task defaults come from `.env`. No hardcoded values in YAML — every param uses `${VAR}` with envsubst. Fallback defaults are in `scripts/lib/common.sh`.

| Variable | Description | Default |
|----------|-------------|---------|
| `PIPELINE_NAMESPACE` | Namespace for pipeline resources | `tekton-pipelines` |
| `RBAC_USER` | RBAC identity | `goods-price-service` |
| `GIT_REPO_URL` | Service repository URL | `https://github.com/RizkiRachman/goods-price-comparison-service.git` |
| `GIT_REPO_DEFAULT_BRANCH` | Git branch | `main` |
| `IMAGE_NAME` | Container image name | `goods-price-comparison-service` |
| `IMAGE_TAG` | Image tag | `latest` |
| `MAVEN_SETTINGS_PATH` | Maven settings.xml path on VPS for GitHub Packages auth | `/home/deploy/.m2/settings.xml` |
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
| `DATABASE_HOST` | External database host (production). Falls back to POSTGRES_HOST. | `(POSTGRES_HOST)` |
| `DATABASE_PORT` | External database port (production). Falls back to POSTGRES_PORT. | `(POSTGRES_PORT)` |
| `MIGRATIONS_PATH` | Flyway migrations directory | `db/migration` |
| `COMPONENT_NAME` | Component name for Vault path | defaults to `DEPLOYMENT_NAME` |
| `GRAVITEE_HOST` | Gravitee APIM Management API host | `gravitee-host` |
| `GRAVITEE_PORT` | Gravitee APIM Management API port | `8083` |
| `GRAVITEE_ORGANIZATION` | Gravitee organization ID | `DEFAULT` |
| `GRAVITEE_ENVIRONMENT` | Gravitee environment ID | `DEFAULT` |
| `GRAVITEE_CONTEXT_PATH` | Gateway context path for this API | `/<DEPLOYMENT_NAME>` |
| `GRAVITEE_BACKEND_URL` | Backend URL Gravitee Gateway proxies to | empty (auto: K8s Service DNS) |
| `INFRA_GRAVITEE_MOUNT` | Vault path for Gravitee admin credentials | `local/infrastructure` |
| `GRAVITEE_VERSION` | Gravitee major version (`v3`/`v4`/empty) | empty (auto-detect) |
| `KUBECTL_IMAGE` | kubectl container image | `bitnami/kubectl:latest` |
| `MAVEN_IMAGE` | Maven container image | `maven:3.9-eclipse-temurin-17` |
| `KANIKO_IMAGE` | Kaniko container image | `gcr.io/kaniko-project/executor:latest` |

## Directory Structure

```
├── .env.template              # Environment variables template
├── installation/              # One-time setup scripts
│   ├── register-resources.sh                #   Health check → Terraform → K8s resources
│   ├── setup-vps.sh                 #   Full VPS setup from scratch
│   └── setup/                 #   Individual setup modules
│       ├── 01-users.sh
│       ├── 02-deps.sh
│       ├── 03-clone-repos.sh
│       └── 04-systemd.sh
├── components/                # Infrastructure definitions
│   ├── tekton/
│   │   ├── tasks/             #   All Tekton task definitions (flat)
│   │   │   ├── cleanup.yaml
│   │   │   ├── maven-build.yaml
│   │   │   ├── maven-test.yaml
│   │   │   ├── sast-scan.yaml
│   │   │   ├── docker-build.yaml
│   │   │   ├── db-provision.yaml
│   │   │   ├── db-migrate.yaml
│   │   │   ├── config-apply.yaml
│   │   │   ├── deploy.yaml
│   │   │   ├── dast-scan.yaml
│   │   │   ├── gravitee-register.yaml
│   │   │   └── vps-deploy.yaml
│   │   └── pipelines/         #   Pipeline definitions
│   │       ├── pipeline.yaml
│   │       ├── pipeline-run.yaml
│   │       ├── security-pipeline.yaml
│   │       └── security-run.yaml
│   ├── kubernetes/            # K8s resource definitions
│   │   ├── rbac/              #   Scoped RBAC for service permissions
│   │   │   ├── pipeline-role.yaml
│   │   │   ├── pipeline-rolebinding.yaml
│   │   │   ├── deployment-role.yaml
│   │   │   ├── deployment-rolebinding.yaml
│   │   │   ├── service-account.yaml
│   │   │   └── tekton-dashboard-role.yaml
│   │   ├── storage/           #   Persistent Volume Claims
│   │   │   ├── workspace-pvc.yaml
│   │   │   └── maven-cache-pvc.yaml
│   │   ├── services/          #   Host gateway endpoints
│   │   │   ├── host-services.yaml
│   │   │   └── host-services-gravitee.yaml
│   │   └── app/               #   Deployment templates
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   ├── vps/                   # VPS operational scripts
│   │   ├── caddy/             #   Caddy management
│   │   │   └── control.sh
│   │   ├── cloudflare/
│   │   │   └── tunnel.sh      #   Cloudflare Tunnel setup
│   │   └── services/
│   │       ├── logs.sh        #   Tail systemd logs
│   │       ├── dashboard.sh   #   Frontend management
│   │       ├── deploy-dashboard.sh
│   │       └── status.sh      #   Cluster + Gravitee status
│   └── terraform/             # Vault → K8s secrets
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── README.md
│       ├── terraform.tfvars.example
│       └── modules/
│           ├── vault-data/
│           ├── k8s-maven-credentials/
│           ├── k8s-vault-token/
│           └── k8s-vps-ssh/
├── docs/                      # Documentation
│   └── vps-setup-guide.md     #   Complete VPS setup guide
├── diagrams/                  # Architecture diagrams (Python + PNG)
│   ├── generate.sh            #   Regenerate all diagrams
│   ├── requirements.txt       #   Python deps
│   ├── architecture.py        #   System infrastructure
│   ├── pipeline.py            #   CI/CD pipeline flow
│   ├── data-flow.py           #   Data flow
│   └── *.png                  #   Generated PNG diagrams
├── helpers/                   # Development helper scripts
│   └── port-forward.sh        #   SSH tunnel for local dev
├── scripts/
    │   ├── common.sh          #   Shared: logging, spinner, timer, env, checks
    │   ├── k8s.sh             #   Kubernetes helper functions
    │   └── vault.sh           #   Vault helper functions
    ├── stages/
    │   ├── init-infra.sh      #   Terraform init + Vault check
    │   └── pipeline-run.sh    #   Trigger Tekton PipelineRun + wait
    ├── apply.sh               #   Full pipeline: clone → build → test → image → deploy
    ├── apply-production.sh    #   Production pipeline: same as apply but external DB
    ├── security.sh            #   Security scan: SAST + DAST analysis
    ├── destroy.sh             #   Teardown: delete all service resources
    └── clean-runs.sh               #   Delete PipelineRuns/TaskRuns
```

## RBAC Scoping

The `components/kubernetes/rbac/` directory defines scoped `Role` + `RoleBinding` resources:

| Allowed | Blocked (shared infra) |
|---------|----------------------|
| Tasks, TaskRuns, Pipelines, PipelineRuns | ServiceAccount `tekton-sa` |
| PVCs (workspace, maven-cache) | ClusterRole `tekton-sa-role` |
| Secrets (`github-maven-credentials`, `maven-settings-secret`) | ClusterRoleBinding `tekton-sa-binding` |
| Pods, Pods/log (read-only) | Secret `registry-credentials` |
| Deployments, ReplicaSets | |
| ConfigMaps, Services, Endpoints | |

## Precautions

- After completing any task or making changes, Claude will review all modified files and command outputs before reporting the work as done.
- This includes verifying that K8s resources are correctly applied, scripts produce expected output, and no regressions were introduced.

## Prerequisites

- [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) running with k3d cluster, Tekton, and Vault
- `kubectl` configured to use the dev-infra cluster context
- `terraform` >= 1.0 installed
- Vault seeded with GitHub credentials at `local/infrastructure/github`
- Vault seeded with database credentials at `local/infrastructure/database`
- Vault seeded with Gravitee credentials at `local/infrastructure/gravitee` (keys: `username`, `password`)
- `vault-host`, `postgres-host`, and `gravitee-host` Services+Endpoints in `tekton-pipelines` namespace

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

# Test Gravitee connectivity from cluster
kubectl run -n tekton-pipelines test-gravitee --image=curlimages/curl -it --rm -- \
  curl -s http://gravitee-host:8083/management/apis

# View gravitee-register task logs
kubectl logs -n tekton-pipelines -l tekton.dev/task=gravitee-register --all-containers

# Clean up failed PipelineRuns
./scripts/clean-runs.sh --failed
```
