variable "namespace" {
  description = "Kubernetes namespace where secrets are created"
  type        = string
}

variable "github_username" {
  description = "GitHub username for Maven Packages authentication"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub PAT for Maven Packages authentication"
  type        = string
  sensitive   = true
}
