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

output "vps_ssh_private_key" {
  description = "VPS SSH private key from Vault"
  value       = data.vault_kv_secret_v2.vps.data.SSH_PRIVATE_KEY
  sensitive   = true
}

output "vps_ssh_user" {
  description = "VPS SSH username from Vault"
  value       = data.vault_kv_secret_v2.vps.data.SSH_USER
}

output "vps_ssh_host" {
  description = "VPS SSH host from Vault"
  value       = data.vault_kv_secret_v2.vps.data.SSH_HOST
}

output "vps_ssh_port" {
  description = "VPS SSH port from Vault"
  value       = data.vault_kv_secret_v2.vps.data.SSH_PORT
}
