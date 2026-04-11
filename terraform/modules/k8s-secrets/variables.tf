variable "namespace" {
  description = "Kubernetes namespace for secrets"
  type        = string
}

variable "github_username" {
  description = "GitHub username for Maven Packages"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub token for Maven Packages"
  type        = string
  sensitive   = true
}
