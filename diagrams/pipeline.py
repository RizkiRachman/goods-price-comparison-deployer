#!/usr/bin/env python3
"""CI/CD Pipeline Flow Diagram.

Shows the Tekton pipeline tasks and their execution order for local and production mode.

Usage: python diagrams/pipeline.py
"""

from diagrams import Diagram, Cluster
from diagrams.onprem.ci import Jenkins  # stand-in for Tekton
from diagrams.onprem.vcs import Github
from diagrams.onprem.container import Docker
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.security import Vault
from diagrams.onprem.iac import Terraform
from diagrams.programming.language import Java, NodeJS, Bash
from diagrams.onprem.network import Internet, Caddy
from diagrams.k8s.compute import Pod, Deploy
from diagrams.k8s.podconfig import Secret
from diagrams.programming.framework import Spring

graph_attr = {
    "fontsize": "20",
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

with Diagram("CI/CD Pipeline Flow", show=False,
             filename="diagrams/pipeline", graph_attr=graph_attr,
             node_attr=node_attr, edge_attr=edge_attr):

    # ── Source ──
    github = Github("GitHub\nSource Code")

    # ── Pipeline Tasks ──
    with Cluster("Tekton Pipeline (k3d cluster)"):
        cleanup = Bash("1. Cleanup\n(workspace)")
        clone = Github("2. Clone\n(git-clone)")
        build = Java("3. Build\n(mvn clean install)")
        test = Java("4. Test\n(mvn verify)")

        with Cluster("Local Mode Only"):
            sast = Bash("5a. SAST Scan")
            image = Docker("6a. Build Image\n(Kaniko)")
            deploy_k8s = Deploy("7a. Deploy\n(kubectl)")

        with Cluster("Production Mode Only"):
            db_provision = PostgreSQL("5b. DB Provision\n(create user + DB)")
            db_migrate = PostgreSQL("6b. DB Migrate\n(Flyway)")
            config = Bash("7b. Config\n(ConfigMap apply)")
            vps_deploy = Caddy("8b. VPS Deploy\n(git pull + mvn + restart)")

        register = Internet("9. Gravitee\nRegister API")

    # ── Credential Sources ──
    with Cluster("Credential Flow"):
        vault = Vault("Vault\n(secrets)")
        tf = Terraform("Terraform")
        k8s_secret = Secret("K8s Secrets")

    # ── Edges ──
    cleanup >> clone >> build >> test

    # Local mode path
    test >> sast >> image >> deploy_k8s >> register

    # Production mode path
    test >> db_provision >> db_migrate >> config >> vps_deploy >> register

    # Credential flow
    vault >> tf >> k8s_secret >> build
    k8s_secret >> deploy_k8s
    k8s_secret >> vps_deploy

    # Annotations
    github >> clone
