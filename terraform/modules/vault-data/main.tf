# Module: vault-data
# Reads service-scoped secrets from Vault KV v2

data "vault_kv_secret_v2" "github" {
  mount = var.vault_mount
  name  = var.github_secret_name
}
