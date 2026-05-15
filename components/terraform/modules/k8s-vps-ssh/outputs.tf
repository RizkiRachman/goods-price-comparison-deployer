output "vps_ssh_secret_name" {
  description = "K8s secret name for VPS SSH credentials"
  value       = kubernetes_secret_v1.vps_ssh.metadata[0].name
}
