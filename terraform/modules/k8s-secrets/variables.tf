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

# Database credentials variables
variable "db_host" {
  description = "Database host"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Database port"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
