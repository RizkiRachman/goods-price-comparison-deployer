# Module: k8s-vault-token
# Owns the vault-token K8s secret consumed by pipeline task pods (db-provision,
# db-migrate, config-apply) to authenticate against the Vault API.
# Intentionally separate from Maven credentials — different owner, different rotation policy.

resource "kubernetes_secret_v1" "vault_token" {
  metadata {
    name      = "vault-token"
    namespace = var.namespace
  }

  data = {
    token = var.vault_token
  }
}
