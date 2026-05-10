<a id="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]

<br />
<div align="center">
  <h3 align="center">Goods Price Comparison — Deployer</h3>
  <p align="center">
    Service-specific CI/CD pipeline definitions for building and deploying the goods-price-comparison-service
    <br />
    <a href="https://github.com/RizkiRachman/goods-price-comparison-service"><strong>Explore the service repo »</strong></a>
    <br />
    <br />
    <a href="#getting-started">Get Started</a>
    &middot;
    <a href="https://github.com/RizkiRachman/dev-infrastructure">Dev Infrastructure</a>
  </p>
</div>

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#architecture">Architecture</a></li>
    <li><a href="#built-with">Built With</a></li>
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#pipeline-flow">Pipeline Flow</a></li>
    <li><a href="#scripts">Scripts</a></li>
    <li><a href="#environment-variables">Environment Variables</a></li>
    <li><a href="#directory-structure">Directory Structure</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>

## About The Project

Service-specific CI/CD pipeline definitions for building and deploying the [goods-price-comparison-service](https://github.com/RizkiRachman/goods-price-comparison-service). Integrates with the shared [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) Tekton server.

All builds run **in-cluster via Tekton** — no local Maven or Docker required.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Architecture

```
dev-infrastructure (shared)                    this repo (deployer)
─────────────────────────                      ──────────────────────────────────
k3d cluster + registry                         terraform/          Vault → K8s secrets
Tekton Pipelines/Dashboard                     tasks/              Tekton task definitions (categorized)
Namespace, SA, ClusterRole, registry secret    pipelines/          Pipeline + PipelineRun templates
Vault + PostgreSQL (on host)                   k8s-setup/          Scoped RBAC + Storage
Gravitee APIM (on host)                        scripts/            init / apply / security / destroy
                                               templates/          K8s deployment + service templates
```

The shared infrastructure is managed by `dev-infrastructure`. This deployer registers service-specific resources (tasks, pipeline, PVCs, secrets) into the shared `tekton-pipelines` namespace.

### Credential Flow

```
Vault (local/infrastructure/github)  ──►  Terraform apply  ──►  K8s Secrets
  GITHUB_USERNAME, GITHUB_TOKEN                                      github-maven-credentials
                                                                     maven-settings-secret
```

- **Vault** stores the source of truth (managed by dev-infrastructure)
- **Terraform** reads Vault and creates K8s secrets declaratively
- **Tekton tasks** reference K8s secrets (no changes to task definitions)

### Database Provisioning

The `db-provision` task automatically:
1. Verifies Vault connectivity and token validity
2. Reads infrastructure DB credentials from Vault (`local/infrastructure/data/database`)
3. Checks if component credentials already exist (skips if valid, re-provisions if password is empty)
4. Generates a random 32-char password (Alpine-compatible)
5. Creates/updates the database and user in PostgreSQL
6. Pushes credentials to Vault (`local/component/<service-name>`)

Passwords are masked in logs: `6e****ae (32 chars)`.

### RBAC Scoping

The `k8s-setup/rbac/` directory defines scoped `Role` + `RoleBinding` resources:

| Allowed | Blocked (shared infra) |
|---------|----------------------|
| Tasks, TaskRuns, Pipelines, PipelineRuns | ServiceAccount `tekton-sa` |
| PVCs (workspace, maven-cache) | ClusterRole `tekton-sa-role` |
| Secrets (`github-maven-credentials`, `maven-settings-secret`) | ClusterRoleBinding `tekton-sa-binding` |
| Pods, Pods/log (read-only) | Secret `registry-credentials` |
| Deployments, ReplicaSets | |
| ConfigMaps, Services, Endpoints | |

### Host Connectivity

Vault, PostgreSQL, and Gravitee APIM run on the **host machine** (outside the k3d cluster). Pipeline pods need `vault-host`, `postgres-host`, and `gravitee-host` Services with manual Endpoints to reach them.

> **Important**: `host.k3d.internal` does NOT resolve from within pods. Use the Service+Endpoint approach instead.

The Services must be in the **same namespace as Tekton pods** (`tekton-pipelines`), otherwise DNS won't resolve.

```bash
# Verify connectivity from inside the cluster
kubectl run -n tekton-pipelines test-vault --image=curlimages/curl -it --rm -- \
  curl -s http://vault-host:8201/v1/sys/health
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Built With

* [![Tekton](https://img.shields.io/badge/Tekton-FF6600?style=for-the-badge&logo=tekton&logoColor=white)](https://tekton.dev/)
* [![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
* [![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
* [![Vault](https://img.shields.io/badge/Vault-FFDD57?style=for-the-badge&logo=vault&logoColor=black)](https://www.vaultproject.io/)
* [![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
* [![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
* [![Flyway](https://img.shields.io/badge/Flyway-CC0200?style=for-the-badge&logo=flyway&logoColor=white)](https://flywaydb.org/)
* [![Gravitee](https://img.shields.io/badge/Gravitee-2A9D8F?style=for-the-badge&logo=gravitee&logoColor=white)](https://www.gravitee.io/)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

### Prerequisites

- [dev-infrastructure](https://github.com/RizkiRachman/dev-infrastructure) running with k3d cluster, Tekton, and Vault
- `kubectl` configured to use the dev-infra cluster context
- `terraform` >= 1.0 installed
- Vault seeded with GitHub credentials at `local/infrastructure/github`
- Vault seeded with database credentials at `local/infrastructure/database`
- Vault seeded with Gravitee credentials at `local/infrastructure/gravitee` (keys: `username`, `password`)
- `vault-host`, `postgres-host`, and `gravitee-host` Services+Endpoints in `tekton-pipelines` namespace

### Installation

1. Start dev-infrastructure:
   ```bash
   cd ../dev-infrastructure && ./scripts/init.sh
   ```

2. Configure this repo:
   ```bash
   cp .env.template .env
   cd terraform
   cp terraform.tfvars.example terraform.tfvars  # Set vault_token
   cd ..
   ```

3. Create host-proxy services (Vault + PostgreSQL + Gravitee access from pods). Replace `192.168.x.x` with your host IP:
   ```bash
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
   ```

4. Initialize (one-time, or when task/pipeline definitions change):
   ```bash
   ./scripts/init.sh
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

### Run the pipeline

```bash
# Full: clone → build → test → image → db-provision → db-migrate → deploy → gravitee-register
./scripts/apply.sh

# With external database (production)
DATABASE_HOST=my-db.example.com DATABASE_PORT=5432 ./scripts/apply-production.sh

# Security scan: SAST + DAST analysis
./scripts/security.sh
```

### Pipeline Flow

```
cleanup → clone → build → test → build-image → db-provision → db-migrate → deploy → gravitee-register
                                     ────────────   ────────────                     ──────────────────
                                     (full mode)    (full mode)                     (full mode)
```

| Mode | Tasks executed | Skipped |
|------|---------------|---------|
| `full` (apply) | all tasks | — |
| `security` | cleanup → clone → build → test → sast-scan → build-image → deploy → dast-scan | db-provision, db-migrate, gravitee-register |
| `production` | all tasks (same as full) | — (uses external database via DATABASE_HOST) |

Tasks are skipped via Tekton `when` expressions — no separate pipeline definition needed.

### Scripts

| Script | What it does | When to use |
|--------|-------------|-------------|
| `init.sh` | Health check → Terraform apply → K8s resources (RBAC, PVCs, tasks, pipeline) | Once, or when YAML definitions change |
| `apply.sh` | Full pipeline run (local dev database) | Every code change |
| `apply-production.sh` | Full pipeline run (external database via DATABASE_HOST) | Deploying with external/managed DB |
| `destroy.sh` | Delete all service resources | Full teardown |
| `clean.sh` | Delete PipelineRuns/TaskRuns | Free disk or clean failed runs |
| `security.sh` | Security scan: SAST + DAST analysis | Security validation |

#### clean.sh options

```bash
./scripts/clean.sh                  # Interactive: choose what to clean
./scripts/clean.sh --failed         # Delete only failed runs
./scripts/clean.sh --all            # Delete all runs
./scripts/clean.sh --older-than 7   # Delete runs older than 7 days
./scripts/clean.sh --all --yes      # Skip confirmation
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

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
| `DATABASE_HOST` | External database host (production). Falls back to POSTGRES_HOST | `(POSTGRES_HOST)` |
| `DATABASE_PORT` | External database port (production). Falls back to POSTGRES_PORT | `(POSTGRES_PORT)` |
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

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Directory Structure

```
├── .env.template              # Environment variables template
├── k8s-setup/                 # RBAC and storage configurations
│   ├── rbac/                  #   Scoped RBAC for service permissions
│   │   ├── pipeline-role.yaml
│   │   ├── pipeline-rolebinding.yaml
│   │   ├── deployment-role.yaml
│   │   ├── deployment-rolebinding.yaml
│   │   ├── service-account.yaml
│   │   └── tekton-dashboard-role.yaml
│   ├── storage/               #   Persistent Volume Claims
│   │   ├── workspace-pvc.yaml
│   │   └── maven-cache-pvc.yaml
│   ├── host-services.yaml
│   └── host-services-gravitee.yaml
├── tasks/                     # Tekton task definitions (categorized)
│   ├── build/
│   │   ├── cleanup.yaml
│   │   ├── maven-build.yaml
│   │   ├── maven-test.yaml
│   │   └── sast-scan.yaml
│   ├── image/
│   │   └── docker-build.yaml
│   ├── database/
│   │   ├── db-provision.yaml
│   │   └── db-migrate.yaml
│   └── deploy/
│       ├── config-apply.yaml
│       ├── deploy.yaml
│       ├── dast-scan.yaml
│       └── gravitee-register.yaml
├── pipelines/                 # Tekton pipeline definitions
│   ├── pipeline-init.yaml
│   ├── pipeline-plan-apply.yaml
│   ├── pipeline-plan-apply-production.yaml
│   ├── pipeline-security.yaml
│   └── pipeline-security-run.yaml
├── templates/                 # K8s deployment templates
│   ├── deployment.yaml
│   └── service.yaml
├── terraform/                 # Vault → K8s secrets
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vault-data/
│       ├── k8s-maven-credentials/
│       └── k8s-vault-token/
└── scripts/
    ├── lib/
    │   ├── common.sh
    │   ├── k8s.sh
    │   └── vault.sh
    ├── stages/
    │   ├── init-infra.sh
    │   └── pipeline-run.sh
    ├── init.sh
    ├── apply.sh
    ├── apply-production.sh
    ├── security.sh
    ├── destroy.sh
    └── clean.sh
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

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
./scripts/clean.sh --failed
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contact

Rizki Rachman - [@RizkiRachman](https://github.com/RizkiRachman)

Project Link: [https://github.com/RizkiRachman/goods-price-comparison-deployer](https://github.com/RizkiRachman/goods-price-comparison-deployer)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[contributors-shield]: https://img.shields.io/github/contributors/RizkiRachman/goods-price-comparison-deployer.svg?style=for-the-badge
[contributors-url]: https://github.com/RizkiRachman/goods-price-comparison-deployer/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/RizkiRachman/goods-price-comparison-deployer.svg?style=for-the-badge
[forks-url]: https://github.com/RizkiRachman/goods-price-comparison-deployer/network/members
[stars-shield]: https://img.shields.io/github/stars/RizkiRachman/goods-price-comparison-deployer.svg?style=for-the-badge
[stars-url]: https://github.com/RizkiRachman/goods-price-comparison-deployer/stargazers
[issues-shield]: https://img.shields.io/github/issues/RizkiRachman/goods-price-comparison-deployer.svg?style=for-the-badge
[issues-url]: https://github.com/RizkiRachman/goods-price-comparison-deployer/issues
