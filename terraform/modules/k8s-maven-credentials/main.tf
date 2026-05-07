# Module: k8s-maven-credentials
# Owns the K8s secrets consumed by Maven build tasks.
# Scope: github-maven-credentials (raw key/token) + maven-settings-secret (settings.xml).
# These two resources share the same GitHub credential inputs and rotate together.

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
