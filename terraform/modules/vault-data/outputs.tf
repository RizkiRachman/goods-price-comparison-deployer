output "github_username" {
  description = "GitHub username from Vault"
  value       = data.vault_kv_secret_v2.github.data.GITHUB_USERNAME
  sensitive   = true
}

output "github_token" {
  description = "GitHub token from Vault"
  value       = data.vault_kv_secret_v2.github.data.GITHUB_TOKEN
  sensitive   = true
}
