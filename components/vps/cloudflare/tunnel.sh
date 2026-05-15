#!/bin/bash
# Setup Cloudflare Tunnel on VPS to expose service publicly
#
# Creates an authenticated tunnel from VPS → localhost:80 (Caddy)
# Caddy handles routing: /v1/* → localhost:8080, /* → serve dashboard dist/
#
# Usage:
#   CLOUDFLARE_TUNNEL_TOKEN="<token>" ./ops/tunnel-setup.sh
#
# Prerequisites:
#   - VPS accessible via SSH (sumopod-root alias)
#   - Caddy running on port 80
#   - Cloudflare account with domain managed
#   - Tunnel already created in Cloudflare Zero Trust dashboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Configuration ──────────────────────────────────────────

SSH_DEST="vps-root"
TUNNEL_NAME="goods-price-service"

# ── Verify tunnel token ────────────────────────────────────

echo "=== Cloudflare Tunnel Setup ==="

if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "ERROR: CLOUDFLARE_TUNNEL_TOKEN not set."
    echo ""
    echo "  To get your tunnel token:"
    echo "    1. Go to: https://dash.cloudflare.com/login"
    echo "    2. Navigate to: Zero Trust → Networks → Tunnels"
    echo "    3. Click the tunnel or create a new one"
    echo "    4. Copy the token (looks like: eyJh...)"
    echo "    5. Run: export CLOUDFLARE_TUNNEL_TOKEN='<your-token>'"
    exit 1
fi

echo "VPS:       ${SSH_DEST}"
echo "Tunnel:    ${TUNNEL_NAME}"
echo ""

# ── Step 1: Install cloudflared ────────────────────────────

echo "[1/4] Installing cloudflared on VPS..."
ssh "$SSH_DEST" '
which cloudflared &>/dev/null && {
    echo "  cloudflared already installed: $(cloudflared --version)"
} || {
    curl -sSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb && \
    dpkg -i /tmp/cloudflared.deb && \
    rm /tmp/cloudflared.deb && \
    echo "  Installed: $(cloudflared --version)"
}' 2>&1
echo ""

# ── Step 2: Install as service with token ──────────────────

echo "[2/4] Installing cloudflared service with token..."
ssh "$SSH_DEST" "
cloudflared service uninstall 2>/dev/null || true
cloudflared service install '${CLOUDFLARE_TUNNEL_TOKEN}'
" 2>&1
echo ""

# ── Step 3: Create config with Caddy routing ───────────────

echo "[3/4] Creating /etc/cloudflared/config.yml..."
ssh "$SSH_DEST" "
# Get tunnel ID from credentials file
TUNNEL_ID=\$(cat /etc/cloudflared/*.json 2>/dev/null | grep -o '\"TunnelID\": \"[^\"]*\"' | head -1 | cut -d'\"' -f4)
if [ -z \"\$TUNNEL_ID\" ]; then
    echo '  ERROR: Could not find tunnel credentials.'
    echo '  Make sure cloudflared service install completed successfully.'
    echo '  Check: ls -la /etc/cloudflared/*.json'
    exit 1
fi
echo '  Tunnel ID: \$TUNNEL_ID'

# Write config
cat > /etc/cloudflared/config.yml << EOF
tunnel: \$TUNNEL_ID
credentials-file: /etc/cloudflared/\${TUNNEL_ID}.json
ingress:
  - hostname: aneh.biz.id
    service: http://localhost:80
  - service: http_status:404
EOF
echo '  Config written'
" 2>&1
echo ""

# ── Step 4: Start service and verify ───────────────────────

echo "[4/4] Starting cloudflared service..."
ssh "$SSH_DEST" "
systemctl daemon-reload
systemctl enable --now cloudflared
sleep 3
systemctl is-active cloudflared
" 2>&1
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Architecture:"
echo "  aneh.biz.id → Cloudflare Tunnel → localhost:80 (Caddy)"
echo "    /v1/*, /v2/*     → proxy → localhost:8080 (backend)"
echo "    /*                → serve → dist/ (dashboard FE)"
echo ""
echo "After setup, in Cloudflare Dashboard:"
echo "  DNS → Add CNAME record:"
echo "    Type: CNAME, Name: @, Target: <tunnel-id>.cfargotunnel.com, Proxy: ☁️"
echo ""
echo "Useful commands:"
echo "  systemctl status cloudflared"
echo "  journalctl -u cloudflared -f"
echo "  cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate"
