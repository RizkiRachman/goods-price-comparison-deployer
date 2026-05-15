# VPS Setup Guide — Sumopod

Complete end-to-end guide for setting up the production VPS from scratch. Covers everything from SSH keys to CI/CD integration.

**VPS:** `43.129.38.221` (2 cores, 2GB RAM, 40GB storage)  
**Domain:** `aneh.biz.id` & `www.aneh.biz.id`  
**External DB:** `pgsql-dbas-jkt-001.sumobase.my.id:65432`  
**App port:** `8080` (local-only, proxied through Caddy)  

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [SSH Key Setup](#2-ssh-key-setup)
3. [User & Security Setup](#3-user--security-setup)
4. [System Dependencies](#4-system-dependencies)
5. [Clone & Maven Auth](#5-clone--maven-auth)
6. [Systemd Services](#6-systemd-services)
7. [Database Migrations](#7-database-migrations)
8. [Reverse Proxy (Caddy)](#8-reverse-proxy-caddy)
9. [Cloudflare DNS + SSL](#9-cloudflare-dns--ssl)
10. [CI/CD Integration](#10-cicd-integration)
11. [Frontend Dashboard](#11-frontend-dashboard)
12. [Daily Operations](#12-daily-operations)
13. [Emergency Recovery](#13-emergency-recovery)

---

## 1. Prerequisites

### Cloudflare Account

- Domain `aneh.biz.id` added to Cloudflare
- Cloudflare API token with `Zone:Edit`, `DNS:Edit`, `SSL:Edit` permissions
- SSL/TLS mode set to **Full (strict)**

### Local Machine

- SSH key pair generated (see §2)
- `~/.ssh/config` configured (see §2)
- This deployer repo cloned:
  ```bash
  git clone https://github.com/RizkiRachman/goods-price-comparison-deployer.git
  ```

### VPS Provider

- Root access via web console (VNC/serial) — **essential for emergency recovery**
- VPS running Ubuntu 22.04+

---

## 2. SSH Key Setup

Generate three key pairs for the tiered access model:

```bash
# Admin key (ubuntu + root)
ssh-keygen -t ed25519 -f ~/.ssh/vps-vps -N "" -C "admin@vps"

# Deploy key (for CI/CD pipeline)
ssh-keygen -t ed25519 -f ~/.ssh/vps-deploy -N "" -C "deploy@vps"

# Agent key (read-only monitoring)
ssh-keygen -t ed25519 -f ~/.ssh/vps-agent -N "" -C "agent@vps"

ls -la ~/.ssh/vps-*
```

### Configure SSH Config

Add to `~/.ssh/config`:

```
Host vps
    HostName 43.129.38.221
    User ubuntu
    Port 22
    IdentityFile ~/.ssh/vps-vps

Host vps-root
    HostName 43.129.38.221
    User root
    IdentityFile ~/.ssh/vps-vps
    Port 22

Host vps-deploy
    HostName 43.129.38.221
    User deploy
    IdentityFile ~/.ssh/vps-deploy
    Port 22

Host vps-agent
    HostName 43.129.38.221
    User agent
    IdentityFile ~/.ssh/vps-agent
    Port 22

Host vps-tunnel
    HostName 43.129.38.221
    User ubuntu
    IdentityFile ~/.ssh/vps-vps
    LocalForward 8080 localhost:8080
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

> **Note:** This guide consolidates all setup steps. See [`vps/`](../vps/) for operational scripts.

---

## 3. User & Security Setup

Run these **as root** via VPS web console (or initial password login):

### Create Users

```bash
# System update
apt update && apt upgrade -y

# Create users
useradd -m -d /home/deploy -s /bin/bash deploy
useradd -m -d /home/agent -s /bin/bash agent

# Groups
groupadd -f production
usermod -aG production deploy
usermod -aG production ubuntu
```

### Install SSH Keys

```bash
# Deploy user
mkdir -p /home/deploy/.ssh
echo 'command="/usr/local/bin/deploy-wrapper",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID5cqS889CPFUJBowTMI+2Nx1bZemnN7eyQoK2l1vs2V deploy@vps' > /home/deploy/.ssh/authorized_keys

# Agent user (read-only)
mkdir -p /home/agent/.ssh
echo 'command="/usr/local/bin/agent-wrapper",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5fafx6gUXeBY/M5Cv4LpY+BOtx53Kv7HeJw/sge9J5 agent@vps' > /home/agent/.ssh/authorized_keys

# Root
mkdir -p /root/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPsLxBFdqVTqTZnNfLRGeVTZHXG/3eNQRGALgVquQiiS vps-vps' > /root/.ssh/authorized_keys

# Permissions
chmod 700 /home/deploy/.ssh /home/agent/.ssh /root/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys /home/agent/.ssh/authorized_keys /root/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy
chown -R agent:agent /home/agent
```

> **Important:** Replace the SSH public keys above with your actual generated keys. The pipeline key (`vps-deploy.pub`) must also be stored in Vault at `local/infrastructure/vps` for Tekton CI/CD.

### Install Wrapper Scripts

Create deploy restriction wrapper at `/usr/local/bin/deploy-wrapper`:

```bash
cat > /usr/local/bin/deploy-wrapper << 'EOF'
#!/bin/bash
RESTRICTED_DIR="/home/production/app"
ALLOWED_PREFIXES=(
  "/home/production/app/goods-price-comparison-service"
  "/home/production/app/goods-price-comparison-dashboard"
)
is_path_allowed() {
  local path="$1"
  for prefix in "${ALLOWED_PREFIXES[@]}"; do
    if [[ "$path" == "$prefix"* ]]; then return 0; fi
  done
  return 1
}
CMD="$SSH_ORIGINAL_COMMAND"
if [ -z "$CMD" ]; then echo "Interactive shell denied."; exit 1; fi
# Handle cd prefix
if [[ "$CMD" == cd\ * ]]; then
  CD_DIR=$(echo "$CMD" | sed -n "s/^cd \([^ ]*\).*/\1/p")
  if [ -n "$CD_DIR" ] && is_path_allowed "$CD_DIR"; then
    REAL_CMD=$(echo "$CMD" | sed "s/^cd [^ ]* && //")
    [ -n "$REAL_CMD" ] && CMD="$REAL_CMD" && cd "$CD_DIR"
  else echo "Permission denied"; exit 1; fi
fi
FIRST=$(echo "$CMD" | awk '{print $1}')
case "$FIRST" in
  ls|cat|tail|head|less|more|grep|find|echo|test|\[) exec $CMD ;;
esac
if [ "$FIRST" = "git" ]; then exec $CMD; fi
if [[ "$FIRST" =~ ^(rsync|scp|cp|mv|rm|mkdir|touch)$ ]]; then
  for arg in $CMD; do
    if [[ "$arg" == "/"* ]] && is_path_allowed "$arg"; then exec $CMD; fi
  done
  echo "Permission denied"; exit 1
fi
exec $CMD
EOF
chmod +x /usr/local/bin/deploy-wrapper
```

Create agent read-only wrapper at `/usr/local/bin/agent-wrapper`:

```bash
cat > /usr/local/bin/agent-wrapper << 'EOF'
#!/bin/bash
ALLOWED_COMMANDS=(cat less more tail head ls find grep df du free uptime date ps top htop netstat ss ip ifconfig pwd echo printenv stat file uname hostname curl wget git systemctl journalctl)
CMD="$SSH_ORIGINAL_COMMAND"
if [ -z "$CMD" ]; then echo "Interactive shell denied."; exit 1; fi
FIRST=$(echo "$CMD" | awk '{print $1}')
for allowed in "${ALLOWED_COMMANDS[@]}"; do
  if [ "$FIRST" = "$allowed" ]; then exec $CMD; fi
done
echo "Command not allowed. Read-only access only."; exit 1
EOF
chmod +x /usr/local/bin/agent-wrapper
```

### Passwordless Sudo for Deploy

The pipeline's `vps-deploy` task needs to restart the systemd service and read service logs. The `deploy` user must have passwordless sudo for these specific commands:

```bash
echo 'Defaults:deploy !use_pty
deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart goods-price-comparison-service, /usr/bin/systemctl status goods-price-comparison-service, /usr/bin/journalctl -u goods-price-comparison-service *, /usr/bin/systemctl restart goods-price-comparison-dashboard, /usr/bin/systemctl status goods-price-comparison-dashboard, /usr/bin/journalctl -u goods-price-comparison-dashboard *, /usr/bin/systemctl restart caddy, /usr/bin/systemctl reload caddy, /usr/bin/systemctl status caddy, /usr/bin/journalctl -u caddy *, /usr/bin/systemctl restart cloudflared, /usr/bin/systemctl status cloudflared, /usr/bin/journalctl -u cloudflared *' | sudo tee /etc/sudoers.d/deploy-service
chmod 440 /etc/sudoers.d/deploy-service
visudo -c
```

> **Note on `!use_pty`:** The `Defaults:deploy !use_pty` line disables pseudo-terminal allocation for the deploy user. This is required because the `deploy` user's SSH access is restricted via a wrapper script (`authorized_keys` `command=`), which runs non-interactively without a TTY. The `!use_pty` setting ensures `sudo` commands work from CI/CD scripts without a terminal.
>
> Use `sudo -n` (non-interactive) in scripts to prevent password prompts:
> ```bash
> ssh vps-deploy "sudo -n systemctl status caddy"
> ssh vps-deploy "sudo -n journalctl -u goods-price-service -n 20"
> ```

Verify:
```bash
sudo -l -U deploy
# Should show: (ALL) NOPASSWD: /usr/bin/systemctl restart goods-price-comparison-service, ...
# And: Defaults:deploy !use_pty
```

### Security Hardening

```bash
# SSH hardening
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sshd -t && systemctl restart sshd

# UFW firewall (tunnel-based: only SSH needs to be open)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable
ufw status verbose

# Note: Ports 80 and 443 are NOT opened.
# Cloudflare Tunnel establishes an outbound connection to Cloudflare Edge,
# so all HTTP/HTTPS traffic enters through the tunnel, not through open ports.

# Fail2ban
apt install -y fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
systemctl enable --now fail2ban

# Auto security updates
apt install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades
```

> **Full reference:** [`vps/`](../vps/) — operational scripts for daily management.

---

## 4. System Dependencies

```bash
# Java 17
apt install -y openjdk-17-jdk
java -version

# Maven & Git
apt install -y git maven

# Node.js 22 (for frontend dashboard)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
apt-get install -y nodejs
node --version

# Caddy reverse proxy
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```

---

## 5. Clone & Maven Auth

```bash
# Production directory
mkdir -p /home/production/app
chown -R :production /home/production
chmod 775 /home/production /home/production/app

# Clone service repo
cd /home/production/app
git clone https://github.com/RizkiRachman/goods-price-comparison-service.git
git clone https://github.com/RizkiRachman/goods-price-comparison-dashboard.git
chown -R :production /home/production/app/*
chmod -R g+w /home/production/app/*
git config --global safe.directory "*"

# Maven settings for GitHub Packages
mkdir -p /home/deploy/.m2
cat > /home/deploy/.m2/settings.xml << 'EOF'
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>rizkirachman</username>
      <password>ghp_your_token_here</password>
    </server>
  </servers>
</settings>
EOF
chmod 600 /home/deploy/.m2/settings.xml
chown -R deploy:deploy /home/deploy/.m2

# Verify Maven auth
cd /home/production/app/goods-price-comparison-service
sudo -u deploy mvn dependency:resolve -q -s /home/deploy/.m2/settings.xml
```

> **Note:** The GitHub token needs `read:packages` scope. Store the same token in Vault at `local/infrastructure/github` for the Tekton pipeline.

---

## 6. Systemd Services

### Backend Service

File: `/etc/systemd/system/goods-price-service.service`

```ini
[Unit]
Description=Goods Price Comparison Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=deploy
Group=production
WorkingDirectory=/home/production/app/goods-price-comparison-service
ExecStart=/usr/bin/java -jar /home/production/app/goods-price-comparison-service/target/goods-price-comparison-service-1.0.0-SNAPSHOT.jar
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
EnvironmentFile=/home/production/app/goods-price-comparison-service/.env.production

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
systemctl daemon-reload
systemctl enable goods-price-service
```

### Environment File

Create `/home/production/app/goods-price-comparison-service/.env.production`:

```bash
cat > /home/production/app/goods-price-comparison-service/.env.production << 'ENVEOF'
DATABASE_HOST=pgsql-dbas-jkt-001.sumobase.my.id
DATABASE_PORT=65432
DATABASE_NAME=dbdc0da41e7c16c75f
DATABASE_USERNAME=uYAHr1mwqQOSZt8ek
DATABASE_PASSWORD=1b50632b10ee2ae0bd1b81b8
SERVER_PORT=8080
LLM_SUMOPOD_API_KEY=sk-your-key
ENVEOF
```

---

## 7. Database Migrations

```bash
# Stop service first (frees DB connections)
systemctl stop goods-price-service

# Run Flyway migrations
cd /home/production/app/goods-price-comparison-service
mvn flyway:migrate -Pflyway \
  -DDATABASE_HOST=pgsql-dbas-jkt-001.sumobase.my.id \
  -DDATABASE_PORT=65432 \
  -DDATABASE_NAME=dbdc0da41e7c16c75f \
  -DDATABASE_USERNAME=uYAHr1mwqQOSZt8ek \
  -DDATABASE_PASSWORD=1b50632b10ee2ae0bd1b81b8

# Start service
systemctl start goods-price-service
sleep 5

# Verify
curl -s http://localhost:8080/actuator/health
# Expected: {"status":"UP","components":{"db":{"status":"UP",...}}}
```

---

## 8. Reverse Proxy (Caddy)

Caddy serves as the entry point for all traffic arriving via the Cloudflare Tunnel. It handles two roles:

1. **Serves dashboard static files** from the built `dist/` directory (SPA with `index.html` fallback)
2. **Proxies API calls** (`/v1/*`, `/v2/*`) to the backend on `localhost:8080`

No TLS is needed — the Cloudflare Tunnel terminates TLS at the edge and forwards HTTP to Caddy on `:80`.

### Architecture

```
Browser → aneh.biz.id → Cloudflare Edge (TLS)
  → Cloudflare Tunnel (d847cde0-...)
  → VPS cloudflared → localhost:80
      → Caddy
          ├── /v1/* → proxy → localhost:8080 (backend)
          ├── /v2/* → proxy → localhost:8080 (backend)
          └── /* → serve /home/.../dist/ (dashboard)
```

### Configuration

File: `/etc/caddy/Caddyfile`

```nginx
# Dashboard served by Caddy, API proxied to backend
# Cloudflare tunnel terminates TLS, Caddy only needs HTTP
:80 {
    # API proxy routes (processed first)
    handle /v1/* {
        reverse_proxy localhost:8080
    }
    handle /v2/* {
        reverse_proxy localhost:8080
    }
    handle /actuator/health {
        reverse_proxy localhost:8080
    }

    # Dashboard static files (SPA fallback to index.html)
    handle {
        root * /home/production/app/goods-price-comparison-dashboard/dist
        try_files {path} /index.html
        file_server
    }
}
```

> **Important:** API routes use `handle` blocks (not just `reverse_proxy` directive) to ensure they are matched before the `try_files` catch-all in the file server block.

### Caddy Installation

```bash
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install -y caddy
```

### Start / Restart

```bash
systemctl enable --now caddy
systemctl reload caddy    # After config changes
systemctl restart caddy
```

### Management

```bash
# Via SSH aliases
./vps/caddy/control.sh status       # Check Caddy + DNS + TLS
./vps/caddy/control.sh logs         # Tail Caddy logs
./vps/caddy/control.sh restart      # Restart Caddy
./vps/caddy/control.sh test         # Test aneh.biz.id from local
./vps/caddy/control.sh dig          # DNS propagation check
```

> **Full reference:** [`vps/caddy/control.sh`](../vps/caddy/control.sh)

---

## 9. Cloudflare Tunnel + DNS

The VPS uses **Cloudflare Tunnel** (cloudflared) for connectivity, not a direct A record. The tunnel provides:

- **No open ports** needed (SSH port 22 excluded) — traffic enters via an outbound-only tunnel
- **TLS termination** at Cloudflare Edge — no SSL certificates needed on the VPS
- **Origin security** — Cloudflare proxies traffic through the tunnel to `localhost:80` (Caddy)

### Tunnel Setup

The tunnel was created via `cloudflared tunnel create` and authenticated with a token. DNS is configured via a **CNAME record** pointing to the tunnel endpoint.

### DNS Records

| Type | Name | Value | Proxy |
|------|------|-------|:-----:|
| CNAME | `aneh.biz.id` | `d847cde0-89fd-4f8f-b059-beb6e44c55dc.cfargotunnel.com` | ☁️ Proxied |

### Tunnel Configuration

File: `/etc/cloudflared/config.yml`

```yaml
tunnel: d847cde0-89fd-4f8f-b059-beb6e44c55dc
credentials-file: /etc/cloudflared/d847cde0-89fd-4f8f-b059-beb6e44c55dc.json
ingress:
  - hostname: aneh.biz.id
    service: http://localhost:80
  - service: http_status:404
```

The tunnel uses a long-lived token for authentication:

```bash
cloudflared tunnel run --token <token>
```

### Systemd Service

The tunnel runs as a systemd service (`cloudflared.service`) using the token-based auth method.

### Management

```bash
systemctl restart cloudflared     # Restart tunnel
systemctl status cloudflared      # Check active connections
journalctl -u cloudflared -n 20   # Recent logs
```

### End-to-End Flow

```
Browser ──► aneh.biz.id ──► Cloudflare Edge (TLS)
  ──► Tunnel ──► cloudflared (VPS) ──► localhost:80
    ──► Caddy
      ├── /v1/*, /v2/*  ──► proxy ──► localhost:8080 (backend)
      └── /*              ──► serve  ──► dist/ (dashboard FE)
```

### Verify End-to-End

```bash
# From the VPS itself
curl -s http://localhost:80/                    # Dashboard HTML
curl -s http://localhost:80/actuator/health     # Backend health via Caddy
curl -s http://localhost:80/v1/prices/search    # API via Caddy proxy

# From external (via tunnel)
curl -sI https://aneh.biz.id
curl -s https://aneh.biz.id/actuator/health
```

---

## 10. CI/CD Integration

The Tekton pipeline in this deployer automates production deployments via the `vps-deploy` task.

### Vault Secrets Setup

The pipeline reads VPS credentials from Vault:

```bash
vault kv put local/infrastructure/vps \
  SSH_PRIVATE_KEY="$(cat ~/.ssh/vps-deploy)" \
  SSH_USER=deploy \
  SSH_HOST=43.129.38.221 \
  SSH_PORT=22
```

Then sync to K8s via Terraform:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # Set vault_token
terraform init && terraform apply
cd ..
```

### Run Production Deploy

```bash
./scripts/apply.sh --production
# or
./scripts/apply-production.sh
```

This triggers the `vps-deploy` task which:
1. SSHs as `deploy` user (key from Vault → K8s secret)
2. Verifies git branch is `main`
3. `git pull origin main`
4. `mvn clean install -U` + `mvn package -DskipTests`
5. Reads DB credentials from Vault
6. `mvn flyway:migrate`
7. `systemctl restart goods-price-service` (requires passwordless sudo — see [Passwordless Sudo](#passwordless-sudo-for-deploy))
8. Health check (`curl localhost:8080/actuator/health`)
9. Registers API in Gravitee APIM

---

## 11. Frontend Dashboard

> **Note:** Caddy serves dashboard static files directly from the filesystem at `/home/production/app/goods-price-comparison-dashboard/dist/`. The dashboard systemd service runs `vite preview` (port 5173) but this port is not directly exposed — all external traffic flows through Caddy (port 80), which serves the `dist/` files and proxies API calls to the backend.

### Systemd Service

File: `/etc/systemd/system/goods-price-comparison-dashboard.service`

```ini
[Unit]
Description=Goods Price Comparison Dashboard (Frontend)
After=network.target

[Service]
Type=simple
User=deploy
Group=production
WorkingDirectory=/home/production/app/goods-price-comparison-dashboard
ExecStart=/usr/bin/npm run start
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

### Manage

```bash
# Via ops script
./vps/services/dashboard.sh status       # Check service
./vps/services/dashboard.sh logs         # Tail logs
./vps/services/dashboard.sh restart      # Restart
./vps/services/dashboard.sh build        # Rebuild (npm run build)
./vps/services/dashboard.sh deploy       # Full: git pull → build → restart

./vps/services/deploy-dashboard.sh
```

> **Full reference:** [`vps/services/dashboard.sh`](../vps/services/dashboard.sh) | [`vps/services/deploy-dashboard.sh`](../vps/services/deploy-dashboard.sh)

---

## 12. Daily Operations

### Service Management

```bash
# Backend
ssh vps-root "systemctl status goods-price-service"
ssh vps-root "systemctl restart goods-price-service"
ssh vps-root "journalctl -u goods-price-service -n 50 --no-pager"

# Frontend dashboard
ssh vps-root "systemctl status goods-price-comparison-dashboard"
ssh vps-root "systemctl restart goods-price-comparison-dashboard"

# Caddy reverse proxy
ssh vps-root "systemctl status caddy"
ssh vps-root "systemctl reload caddy"     # After config changes
ssh vps-root "systemctl restart caddy"

# Cloudflare Tunnel
ssh vps-root "systemctl status cloudflared"
ssh vps-root "systemctl restart cloudflared"

# Via ops scripts (from local)
./vps/services/logs.sh -n 50            # Last 50 lines of app logs
./vps/services/logs.sh --caddy          # Caddy logs
./vps/services/logs.sh --since "30m"    # Last 30 minutes
```

### Rebuild & Restart (Manual)

```bash
# Backend
ssh vps-deploy "cd /home/production/app/goods-price-comparison-service && git pull"
ssh vps-root "cd /home/production/app/goods-price-comparison-service && mvn package -DskipTests -s /home/deploy/.m2/settings.xml"
ssh vps-root "systemctl restart goods-price-service"

# Frontend (rebuild dist/ so Caddy serves updated files)
ssh vps-deploy "cd /home/production/app/goods-price-comparison-dashboard && git pull"
ssh vps-root "cd /home/production/app/goods-price-comparison-dashboard && npm run build && systemctl restart goods-price-comparison-dashboard"
```

### Development Tunnel

For local development, forward VPS backend to localhost:

```bash
./helpers/port-forward.sh          # Start tunnel (port 8080)
./helpers/port-forward.sh -s       # Status
./helpers/port-forward.sh -k       # Kill
./helpers/port-forward.sh -p 9090  # Custom local port
```

Requires `autossh` installed locally: `brew install autossh`

> **Full reference:** [`helpers/port-forward.sh`](../helpers/port-forward.sh)

### Security Audit

```bash
# Open ports check
ssh vps-root "ss -tlnp"

# Firewall rules
ssh vps-root "ufw status verbose"

# Fail2ban status
ssh vps-root "fail2ban-client status sshd"

# SSH config
ssh vps-root "grep -E '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config"
```

---

## 13. Emergency Recovery

### VPS Unreachable (UFW Blocked SSH)

Access via **VPS provider web console** (VNC/serial), then:

```bash
# Allow SSH through UFW
ufw allow 22/tcp
ufw reload

# Re-add SSH key if lost
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPsLxBFdqVTqTZnNfLRGeVTZHXG/3eNQRGALgVquQiiS vps-vps" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### SSH Key Rotated

1. Generate new key locally
2. Add public key to VPS via web console
3. Update Vault: `vault kv put local/infrastructure/vps SSH_PRIVATE_KEY="$(cat ~/.ssh/new-key)" SSH_USER=deploy ...`
4. Re-apply Terraform: `cd terraform && terraform apply`

### VPS Completely Locked

Use **rescue mode** from VPS provider:
1. Enable rescue mode in provider dashboard
2. SSH into rescue OS with temporary credentials
3. Mount real disk: `mount /dev/vda1 /mnt`
4. Fix UFW: `chroot /mnt ufw allow 22/tcp`
5. Add SSH key: `echo "key" >> /mnt/home/deploy/.ssh/authorized_keys`
6. Reboot, disable rescue mode

> **Full reference:** See section 3 (Security Hardening) above for UFW/SSH setup.

---

## Reference Map

| Step | Section in this guide | Ops Script |
|------|----------------------|------------|
| SSH keys + users | §2 | — |
| System deps | §4 | — |
| Maven auth | §5 | — |
| Systemd services | §6 | — |
| Database | §7 | — |
| Caddy reverse proxy | §8 | `vps/caddy/control.sh` |
| Cloudflare Tunnel + DNS | §9 | `vps/cloudflare/tunnel.sh` |
| Frontend dashboard | §11 | `vps/services/dashboard.sh` |
| Dev SSH tunnel | — | `helpers/port-forward.sh` |
| Logs | §12 | `vps/services/logs.sh` |
| Cluster status | — | `vps/services/status.sh` |
