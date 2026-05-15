#!/usr/bin/env python3
"""Credential Flow Diagram.

Shows how secrets flow from Vault through Terraform to K8s Secrets, then consumed by Tekton tasks.

Usage: python diagrams/credential-flow.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.security import Vault
from diagrams.onprem.iac import Terraform
from diagrams.onprem.ci import Jenkins  # Tekton stand-in
from diagrams.onprem.vcs import Github
from diagrams.k8s.podconfig import Secret
from diagrams.k8s.rbac import SA
from diagrams.programming.language import Bash

graph_attr = {
    "fontsize": "18",
    "bgcolor": "white",
    "fontcolor": "#1f2937",
    "rankdir": "LR",
    "pad": "0.5",
    "splines": "ortho",
}

node_attr = {
    "fontsize": "11",
    "fontcolor": "#1f2937",
}

edge_attr = {
    "color": "#2563eb",
    "fontcolor": "#4b5563",
    "fontsize": "9",
}

with Diagram("Credential Flow", show=False,
             filename="diagrams/credential-flow", graph_attr=graph_attr,
             node_attr=node_attr, edge_attr=edge_attr):

    vault = Vault("Vault\nSecrets Store")

    with Cluster("Terraform (this repo)"):
        tf = Terraform("terraform apply\nReads Vault → Writes K8s")

    with Cluster("Kubernetes"):
        github_secret = Secret("github-maven-credentials\n(GH_USER + GH_TOKEN)")
        settings_secret = Secret("maven-settings-secret\n(settings.xml)")
        vault_secret = Secret("vault-token")
        ssh_secret = Secret("vps-ssh-key\n(SSH key)")

    with Cluster("Tekton Tasks"):
        maven = Bash("maven-build\n(Maven compile)")
        db_provision = Bash("db-provision\n(Create DB + user)")
        db_migrate = Bash("db-migrate\n(Flyway)")
        vps_deploy = Bash("vps-deploy\n(git pull + restart)")
        config = Bash("config-apply\n(Vault props)")

    # Vault → Terraform → K8s Secrets
    vault >> Edge(label="reads") >> tf
    tf >> Edge(label="creates") >> github_secret
    tf >> settings_secret
    tf >> vault_secret
    tf >> ssh_secret

    # K8s Secrets → Tekton Tasks
    github_secret >> maven
    settings_secret >> maven
    vault_secret >> db_provision
    vault_secret >> db_migrate
    vault_secret >> config
    vault_secret >> vps_deploy
    ssh_secret >> vps_deploy
