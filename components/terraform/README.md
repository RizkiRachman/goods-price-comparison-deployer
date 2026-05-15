# Terraform: Vault → Kubernetes Secrets

## Overview

This Terraform configuration reads credentials from **Vault** and creates **Kubernetes secrets** for the goods-price-comparison Tekton pipeline. All secret management flows through Terraform — no `kubectl create secret` anywhere.

```
┌──────────────┐     ┌───────────────────┐     ┌───────────────────────────┐
│    Vault      │     │    Terraform       │     │    Kubernetes Secrets      │
│               │────►│                    │────►│                           │
│ local/        │     │ modules/vault-data │     │ github-maven-credentials  │
│  infrastructure│     │ modules/k8s-secrets│     │ maven-settings-secret     │
└──────────────┘     └───────────────────┘     └───────────────────────────┘
```

## Architecture

### Module Structure

```
terraform/
├── main.tf                          # Orchestrator: providers + module wiring
├── variables.tf                     # Root-level input variables
├── terraform.tfvars.example         # Example values (copy to terraform.tfvars)
└── modules/
    ├── vault-data/                   # Reads secrets from Vault
    │   ├── main.tf                   #   vault_kv_secret_v2 data sources
    │   ├── variables.tf              #   vault_mount, github_secret_name
    │   └── outputs.tf                #   github_username, github_token
    └── k8s-secrets/                  # Creates K8s secrets
        ├── main.tf                   #   kubernetes_secret resources
        ├── variables.tf              #   namespace, github_username, github_token
        ├── outputs.tf                #   secret names
        └── templates/
            └── settings.xml.tpl      #   Maven settings.xml template
```

### Data Flow

```
main.tf
  │
  ├── module.vault_data
  │     │
  │     └── reads Vault KV v2: local/infrastructure/github
  │           └── keys: GITHUB_USERNAME, GITHUB_TOKEN
  │
  └── module.k8s_secrets
        │
        ├── kubernetes_secret.github_maven_credentials
        │     └── data: { username, token }
        │
        └── kubernetes_secret.maven_settings
              └── data: { settings.xml } (generated from template)
```

## Vault Configuration

### Required Secrets

| Vault Mount | Secret Name | Keys | Description |
|-------------|-------------|------|-------------|
| `local/infrastructure` | `github` | `GITHUB_USERNAME`, `GITHUB_TOKEN` | GitHub Packages credentials for Maven |

### Seeding Vault (one-time)

```bash
# Enable KV v2 secrets engine at local/infrastructure path
vault secrets enable -path=local/infrastructure kv-v2

# Put GitHub credentials
vault kv put local/infrastructure/github \
  GITHUB_USERNAME="<your-username>" \
  GITHUB_TOKEN="<your-token>"
```

### Verifying Vault secrets

```bash
vault kv get -mount="local/infrastructure" "github"
```

## Kubernetes Secrets Created

| Secret Name | Namespace | Keys | Used By (Tekton Tasks) |
|-------------|-----------|------|------------------------|
| `github-maven-credentials` | `tekton-pipelines` | `username`, `token` | maven-build, maven-test |
| `maven-settings-secret` | `tekton-pipelines` | `settings.xml` | maven-build, maven-test |

**Note**: The `docker-build` (Kaniko) task does NOT use these secrets — the service repo Dockerfile is a JRE runtime image that `COPY`s the pre-built JAR from the workspace, without running Maven inside Docker.

**Note**: `registry-credentials` is managed by dev-infrastructure, NOT by this Terraform config.

## Usage

Terraform is managed through the action scripts — you don't run `terraform` commands directly:

| Action | Terraform command |
|--------|-------------------|
| `./scripts/init.sh` | `terraform init` + `terraform apply` |
| `./scripts/destroy.sh` | `terraform destroy` |

### First-time setup

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set vault_token
cd ..
./scripts/init.sh
```

### Verify

```bash
# Check Terraform state (secrets registered)
cd terraform && terraform state list
```

## Variables Reference

| Variable | Description | Default | Sensitive |
|----------|-------------|---------|-----------|
| `vault_address` | Vault server address | `http://localhost:8200` | No |
| `vault_token` | Vault root token | — | Yes |
| `vault_mount` | Vault KV v2 mount path | `local/infrastructure` | No |
| `github_secret_name` | Vault secret name for GitHub creds | `github` | No |
| `kubeconfig_path` | Path to kubeconfig | `~/.kube/config` | No |
| `kube_context` | Kubernetes context name | `k3d-dev-infra` | No |
| `pipeline_namespace` | Namespace for K8s secrets | `tekton-pipelines` | No |

## Prerequisites

- **Vault** running and accessible (installed via dev-infrastructure)
- **kubectl** configured with k3d cluster context
- **Terraform** >= 1.0 installed
- Vault KV v2 secrets engine enabled at `local/infrastructure`
- GitHub credentials seeded in Vault
