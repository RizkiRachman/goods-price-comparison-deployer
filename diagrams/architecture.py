#!/usr/bin/env python3
"""System Architecture Diagram.

Matches the README ASCII art: shows dev-infrastructure host (Vault, DB, Gravitee, k3d)
+ production VPS (Tunnel -> Caddy -> FE/BE) + GitHub.

Usage: python diagrams/architecture.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import User
from diagrams.onprem.network import Internet, Caddy
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.security import Vault
from diagrams.onprem.vcs import Github
from diagrams.onprem.iac import Terraform
from diagrams.onprem.container import Docker, K3S
from diagrams.programming.framework import Spring, React
from diagrams.programming.language import Java, NodeJS
from diagrams.onprem.workflow import Airflow  # Tekton stand-in
from diagrams.k8s.compute import Deploy
from diagrams.k8s.podconfig import Secret
from diagrams.k8s.storage import PVC

graph_attr = {
    "fontsize": "18",
    "bgcolor": "white",
    "fontcolor": "#1f2937",
    "rankdir": "TB",
    "pad": "0.5",
    "splines": "ortho",
    "compound": "true",
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

with Diagram("System Architecture Overview", show=False,
             filename="diagrams/architecture", graph_attr=graph_attr,
             node_attr=node_attr, edge_attr=edge_attr):

    # ── TOP ROW: Git + Cloudflare ──
    github = Github("GitHub\n(Source + Packages)")
    cloudflare = Internet("Cloudflare\nEdge (TLS)")

    # ── HOST MACHINE (dev-infrastructure Docker) ──
    with Cluster("Host Machine (dev-infrastructure Docker)"):
        vault = Vault("Vault\n:8201")
        pg_dev = PostgreSQL("PostgreSQL\n:5432\n(goods_price)")

        with Cluster("k3d Kubernetes Cluster"):
            tekton = Airflow("Tekton Pipeline\ncleanup \u2192 clone \u2192 build\n\u2192 test \u2192 image \u2192 db\n\u2192 config \u2192 deploy\n\u2192 gravitee-register")
            with Cluster("K8s Resources"):
                deploy = Deploy("Deployment\n:8080")
                secret = Secret("Secrets\n(github-maven,\nvault-token,\nvps-ssh)")
                pvc = PVC("+PVCs")

        tf = Terraform("Terraform\n(this repo)\nvault-data \u2192 k8s-secrets")

    # ── PRODUCTION VPS ──
    with Cluster("Production VPS (43.129.38.221)"):
        tunnel = NodeJS("Cloudflare\nTunnel\n(cloudflared)")
        caddy = Caddy("Caddy\n:80")
        spring = Spring("Backend\n:8080\n(Spring Boot)")
        react = React("Dashboard\n:5173\n(Vite Preview)")

    # ── External DB ──
    pg_prod = PostgreSQL("PostgreSQL\n(managed external)\npgsql-dbas-jkt-001:65432")

    # ── EDGES ──
    # Dev-infrastructure flow
    vault >> Edge(label="reads API") >> tekton
    vault >> tf
    tf >> Edge(label="vault-data \u2192 k8s") >> secret

    # Tekton deploys to K8s
    tekton >> Edge(label="kubectl") >> deploy

    # Production flow
    cloudflare >> tunnel
    tunnel >> caddy
    caddy >> Edge(label="/v1/* /v2/*") >> spring
    caddy >> Edge(label="dist/") >> react

    # Backend to DB
    spring >> Edge(label="JDBC") >> pg_prod

    # GitHub to Tekton (git clone)
    github >> Edge(label="git clone") >> tekton

    # VPS deploy (SSH)
    tekton >> Edge(label="vps-deploy (SSH)", style="dashed") >> spring
    secret >> Edge(style="dashed") >> tekton
