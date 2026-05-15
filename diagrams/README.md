# Architecture Diagrams

Uses [mingrammer/diagrams](https://github.com/mingrammer/diagrams) — diagrams are defined as Python code and rendered via Graphviz. Version-controlled, precise, repeatable.

```bash
./diagrams/generate.sh
```

| File | What it shows |
|------|---------------|
| `architecture.py` | System infrastructure: host machine + production VPS (Tunnel → Caddy → FE/BE) + GitHub |
| `credential-flow.py` | Credential flow: Vault → Terraform → K8s Secrets → Tekton Tasks |
| `pipeline.py` | CI/CD pipeline flow: Tekton tasks in local vs production mode |
| `data-flow.py` | Data flow: HTTP request path, API calls, DB queries |

Regenerate anytime with `./diagrams/generate.sh` (auto-creates venv, installs deps).
