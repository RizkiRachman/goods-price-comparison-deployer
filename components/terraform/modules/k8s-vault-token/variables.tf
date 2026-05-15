variable "namespace" {
  description = "Kubernetes namespace where the secret is created"
  type        = string
}

variable "vault_token" {
  description = "Vault token injected into pipeline task pods for Vault API access"
  type        = string
  sensitive   = true
}
