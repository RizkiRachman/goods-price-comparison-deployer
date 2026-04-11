variable "vault_mount" {
  description = "Vault KV v2 mount path"
  type        = string
  default     = "local/infrastructure"
}

variable "github_secret_name" {
  description = "Vault secret name for GitHub credentials"
  type        = string
  default     = "github"
}

variable "database_secret_name" {
  description = "Vault secret name for database credentials"
  type        = string
  default     = "database"
}
