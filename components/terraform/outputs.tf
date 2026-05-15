output "github_maven_credentials_name" {
  description = "K8s secret name for GitHub Maven credentials"
  value       = module.k8s_maven_credentials.github_maven_credentials_name
}

output "maven_settings_secret_name" {
  description = "K8s secret name for Maven settings.xml"
  value       = module.k8s_maven_credentials.maven_settings_secret_name
}

output "vault_token_secret_name" {
  description = "K8s secret name for the Vault token used by pipeline tasks"
  value       = module.k8s_vault_token.vault_token_secret_name
}

output "vps_ssh_secret_name" {
  description = "K8s secret name for VPS SSH credentials"
  value       = module.k8s_vps_ssh.vps_ssh_secret_name
}
