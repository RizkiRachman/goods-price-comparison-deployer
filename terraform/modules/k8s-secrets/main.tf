# Module: k8s-secrets
# Creates Kubernetes secrets for this service's Tekton pipeline tasks

# GitHub Maven credentials (used by maven-build, maven-test tasks)
resource "kubernetes_secret_v1" "github_maven_credentials" {
  metadata {
    name      = "github-maven-credentials"
    namespace = var.namespace
  }

  data = {
    username = var.github_username
    token    = var.github_token
  }
}

# Maven settings.xml generated from GitHub credentials
resource "kubernetes_secret_v1" "maven_settings" {
  metadata {
    name      = "maven-settings-secret"
    namespace = var.namespace
  }

  data = {
    "settings.xml" = templatefile(
      "${path.module}/templates/settings.xml.tpl",
      {
        username = var.github_username
        token    = var.github_token
      }
    )
  }

  depends_on = [kubernetes_secret_v1.github_maven_credentials]
}
