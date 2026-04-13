# ── Vault Configuration ────────────────────────────────────

variable "vault_address_terraform" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8201"
}

variable "vault_token" {
  description = "Vault root token for authentication"
  type        = string
  sensitive   = true
}

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

# ── Kubernetes Configuration ──────────────────────────────

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context name (k3d cluster)"
  type        = string
  default     = "k3d-dev-infra"
}

# ── Pipeline Configuration ────────────────────────────────

variable "pipeline_namespace" {
  description = "Namespace for Tekton pipeline resources"
  type        = string
  default     = "tekton-pipelines"
}
