variable "namespace" {
  description = "Kubernetes namespace for the secret"
  type        = string
}

variable "ssh_private_key" {
  description = "VPS deploy user SSH private key"
  type        = string
  sensitive   = true
}

variable "ssh_user" {
  description = "VPS SSH username"
  type        = string
}

variable "ssh_host" {
  description = "VPS hostname or IP"
  type        = string
}

variable "ssh_port" {
  description = "VPS SSH port"
  type        = string
  default     = "22"
}
