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

# Database credentials from Vault
output "db_host" {
  description = "Database host from Vault"
  value       = data.vault_kv_secret_v2.database.data.POSTGRES_HOST
  sensitive   = true
}

output "db_port" {
  description = "Database port from Vault"
  value       = data.vault_kv_secret_v2.database.data.POSTGRES_PORT
  sensitive   = true
}

output "db_name" {
  description = "Database name from Vault"
  value       = data.vault_kv_secret_v2.database.data.POSTGRES_DB
  sensitive   = true
}

output "db_username" {
  description = "Database username from Vault"
  value       = data.vault_kv_secret_v2.database.data.POSTGRES_USER
  sensitive   = true
}

output "db_password" {
  description = "Database password from Vault"
  value       = data.vault_kv_secret_v2.database.data.POSTGRES_PASSWORD
  sensitive   = true
}
