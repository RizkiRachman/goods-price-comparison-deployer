# Module: k8s-vps-ssh
# Creates K8s secret containing VPS SSH credentials for the vps-deploy Tekton task.
# Reads from vault-data module outputs.

resource "kubernetes_secret_v1" "vps_ssh" {
  metadata {
    name      = "vps-ssh-key"
    namespace = var.namespace
  }

  data = {
    id_rsa = var.ssh_private_key
    user   = var.ssh_user
    host   = var.ssh_host
    port   = var.ssh_port
  }
}
