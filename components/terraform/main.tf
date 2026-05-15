# Terraform: Vault → Kubernetes Secrets (service-scoped)
# Three-module chain:
#   vault-data              reads GitHub credentials from Vault
#   k8s-maven-credentials   creates Maven build secrets (consumes vault-data outputs)
#   k8s-vault-token         creates the Vault auth token secret (separate lifecycle)
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply

# ── Providers ──────────────────────────────────────────────

provider "vault" {
  address = var.vault_address_terraform
  token   = var.vault_token
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

# ── Data layer: read from Vault ───────────────────────────

module "vault_data" {
  source             = "./modules/vault-data"
  vault_mount        = var.vault_mount
  github_secret_name = var.github_secret_name
}

# ── Secret layer: create K8s secrets ─────────────────────

# Maven build credentials — sourced from Vault, rotates with GitHub PAT.
module "k8s_maven_credentials" {
  source          = "./modules/k8s-maven-credentials"
  namespace       = var.pipeline_namespace
  github_username = module.vault_data.github_username
  github_token    = module.vault_data.github_token
}

# Vault access token — passed directly, rotates independently from Maven creds.
# Used by pipeline tasks (db-provision, db-migrate, config-apply) to call the Vault API.
module "k8s_vault_token" {
  source      = "./modules/k8s-vault-token"
  namespace   = var.pipeline_namespace
  vault_token = var.vault_token
}

# VPS SSH key — used by vps-deploy task for production deployment.
# Sourced from Vault (local/infrastructure/vps), mounted as K8s secret.
module "k8s_vps_ssh" {
  source          = "./modules/k8s-vps-ssh"
  namespace       = var.pipeline_namespace
  ssh_private_key = module.vault_data.vps_ssh_private_key
  ssh_user        = module.vault_data.vps_ssh_user
  ssh_host        = module.vault_data.vps_ssh_host
  ssh_port        = module.vault_data.vps_ssh_port
}

# Note: registry-credentials is managed by dev-infrastructure, NOT by this service.
# Note: database credentials are read by pipeline tasks directly from Vault at runtime.
