# Terraform: Vault → Kubernetes Secrets (service-scoped)
# Orchestrates modules to read from Vault and create K8s secrets.
# Only manages secrets owned by this service — shared infra secrets are NOT managed here.
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply

# ── Providers ──────────────────────────────────────────────

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

# ── Modules ───────────────────────────────────────────────

# Read service-scoped secrets from Vault
module "vault_data" {
  source             = "./modules/vault-data"
  vault_mount        = var.vault_mount
  github_secret_name = var.github_secret_name
}

# Create K8s secrets for Tekton pipeline tasks
module "k8s_secrets" {
  source           = "./modules/k8s-secrets"
  namespace        = var.pipeline_namespace
  github_username  = module.vault_data.github_username
  github_token     = module.vault_data.github_token
}

# Note: registry-credentials is managed by dev-infrastructure, NOT by this service.
