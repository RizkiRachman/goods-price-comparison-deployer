variable "vault_mount" {
  description = "Vault KV v2 mount path for infrastructure secrets"
  type        = string
  default     = "local/infrastructure"
}

variable "github_secret_name" {
  description = "Vault secret name containing GitHub credentials (GITHUB_USERNAME, GITHUB_TOKEN)"
  type        = string
  default     = "github"
}
