# Module: vault-data
# Data-only module — reads infrastructure secrets from Vault KV v2.
# Outputs are consumed by sibling modules that create K8s secrets.

data "vault_kv_secret_v2" "github" {
  mount = var.vault_mount
  name  = var.github_secret_name
}
