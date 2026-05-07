output "vault_token_secret_name" {
  description = "Name of the vault-token K8s secret"
  value       = kubernetes_secret_v1.vault_token.metadata[0].name
}
