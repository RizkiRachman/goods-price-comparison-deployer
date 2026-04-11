output "github_maven_credentials_name" {
  description = "Name of the GitHub Maven credentials secret"
  value       = kubernetes_secret_v1.github_maven_credentials.metadata[0].name
}

output "maven_settings_secret_name" {
  description = "Name of the Maven settings secret"
  value       = kubernetes_secret_v1.maven_settings.metadata[0].name
}
