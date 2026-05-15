#!/usr/bin/env python3
"""Data Flow Diagram.

Shows what data passes through each component in the system.

Usage: python diagrams/data-flow.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import User
from diagrams.onprem.network import Internet, Caddy
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.security import Vault
from diagrams.onprem.vcs import Github
from diagrams.programming.framework import Spring, React
from diagrams.programming.language import NodeJS, JavaScript
from diagrams.onprem.compute import Server

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "fontcolor": "#1f2937",
    "rankdir": "TB",
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

data_edge = Edge(color="#d97706", style="dashed", label="data")
api_edge = Edge(color="#059669", label="API")
static_edge = Edge(color="#7c3aed", label="static files")
tunnel_edge = Edge(color="#2563eb", label="TLS tunnel")

with Diagram("Data Flow", show=False,
             filename="diagrams/data-flow", graph_attr=graph_attr,
             node_attr=node_attr, edge_attr=edge_attr):

    user = User("End User\n(browser)")

    with Cluster("Cloudflare Edge"):
        cf = Internet("Cloudflare\nTLS / WAF / Cache")

    with Cluster("VPS (43.129.38.221)"):
        tunnel = NodeJS("cloudflared")

        caddy = Caddy("Caddy :80")

        with Cluster("Frontend"):
            fe = React("Dashboard\nVite Preview :5173")
            js = JavaScript("dist/\nindex.js + CSS")

        with Cluster("Backend (Spring Boot :8080)"):
            api = Spring("goods-price-\ncomparison-service")
            db_conn = PostgreSQL("Flyway\nMigrations")

    with Cluster("External"):
        db = PostgreSQL("PostgreSQL\n(managed)")

    # ── Request Flow (user -> Cloudflare -> tunnel -> Caddy) ──
    user >> tunnel_edge >> cf >> tunnel_edge >> tunnel
    tunnel >> Edge(color="#58a6ff") >> caddy

    # ── Caddy routing ──
    # Static files (dashboard)
    caddy >> static_edge >> js
    js >> data_edge >> fe

    # API proxy
    caddy >> api_edge >> api

    # ── Backend internal ──
    api >> Edge(label="JDBC", color="#3fb950") >> db
    api >> Edge(label="Flyway", color="#f0883e") >> db_conn
    db_conn >> Edge(label="SQL", color="#3fb950") >> db

    # ── Response Flow (reverse direction) ──
    db >> Edge(label="result sets", color="#3fb950", style="dashed") >> api
    api >> Edge(label="JSON API", color="#3fb950") >> caddy
    fe >> Edge(label="index.html", color="#d2a8ff") >> caddy
    caddy >> Edge(label="HTTP response", color="#58a6ff") >> tunnel
    tunnel >> tunnel_edge >> cf
    cf >> tunnel_edge >> user

    # ── Legend ──
    # Solid lines = request, Dashed = data content
    # Orange = data payload, Green = API calls, Purple = static files, Blue = tunnel
