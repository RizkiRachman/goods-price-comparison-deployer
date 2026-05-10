#!/bin/bash
# Setup Cloudflare Tunnel on VPS to expose service publicly
# Creates an authenticated tunnel from VPS → localhost:8080
# Requires manual DNS configuration in Cloudflare dashboard afterward
#
# Usage:
#   CLOUDFLARE_TUNNEL_TOKEN="<token>" CLOUDFLARE_DOMAIN="api.yourdomain.com" ./scripts/helper/tunnel-setup.sh
#   # or interactive mode (will prompt for token)
#   ./scripts/helper/tunnel-setup.sh
#
# Prerequisites:
#   - VPS accessible via SSH (uses same config as deploy-vps.sh)
#   - Service running on port 8080
#   - Cloudflare account with domain managed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ── Configuration ──────────────────────────────────────────

VPS_USER="${VPS_USER:-ubuntu}"
VPS_SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/sumopod-vps}"

if [ -n "${VPS_HOST:-}" ]; then
    SSH_DEST="${VPS_USER}@${VPS_HOST}"
    SSH_CMD="ssh -i ${VPS_SSH_KEY} -o StrictHostKeyChecking=no ${SSH_DEST}"
else
    SSH_DEST="sumopod"
    SSH_CMD="ssh -o StrictHostKeyChecking=no ${SSH_DEST}"
fi

TUNNEL_NAME="goods-price-service"
SERVICE_PORT=8080

# ── Verify tunnel token ────────────────────────────────────

stage "Cloudflare Tunnel — Setup"

if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    warn "CLOUDFLARE_TUNNEL_TOKEN not set."
    echo ""
    echo "  To get your tunnel token:"
    echo "    1. Go to: https://dash.cloudflare.com/login"
    echo "    2. Navigate to: Zero Trust → Networks → Tunnels"
    echo "    3. Click 'Create a tunnel' → 'Cloudflared'"
    echo "    4. Copy the token (looks like: gAAAAA...)"
    echo "    5. Run export CLOUDFLARE_TUNNEL_TOKEN='<your-token>'"
    exit 1
fi

if [ -z "${CLOUDFLARE_DOMAIN:-}" ]; then
    error "CLOUDFLARE_DOMAIN is required. Set e.g.: CLOUDFLARE_DOMAIN=api.yourdomain.com"
fi

log "VPS:       ${SSH_DEST}"
log "Domain:    ${CLOUDFLARE_DOMAIN}"
log "Service:   localhost:${SERVICE_PORT}"
echo ""

# ── Step 1: Install cloudflared ────────────────────────────

echo "[1/6] Installing cloudflared on VPS..."
INSTALL_OUTPUT=$($SSH_CMD '
which cloudflared &>/dev/null && { 
    cloudflared --version | head -1;
    log "cloudflared already installed"
} || {
    curl -sSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb && \
    sudo dpkg -i /tmp/cloudflared.deb && \
    rm /tmp/cloudflared.deb && \
    cloudflared --version | head -1
}' 2>&1 || true)

echo "$INSTALL_OUTPUT" | grep -i "cloudflared\|already\|error" | tail -3 || true
echo ""

# ── Step 2: Create tunnel ──────────────────────────────────

log "Creating tunnel '${TUNNEL_NAME}' on VPS..."
$SSH_CMD "
sudo cloudflared service uninstall 2>/dev/null || true
sudo cloudflared tunnels create '${TUNNEL_NAME}'
" || warn "Tunnel may already exist, proceeding..."

# Get tunnel UUID
log "Fetching tunnel details..."
TUNNEL_UUID=$(echo "$($SSH_CMD "sudo cloudflared tunnels list | grep '${TUNNEL_NAME}' | awk '{print \$1}'")" | tr -d '\r\n')

if [ -z "$TUNNEL_UUID" ]; then
    TUNNEL_UUID=$($SSH_CMD "cat ~/.cloudflared/*.json 2>/dev/null | grep -o '\"TunnelID\": \"[^\"]*\"' | head -1 | cut -d'\"' -f4)"
fi

if [ -z "$TUNNEL_UUID" ]; then
    error "Failed to get tunnel UUID. Verify your token and try again."
fi

log "Tunnel UUID: ${TUNNEL_UUID}"
echo ""

# ── Step 3: Configure routing ──────────────────────────────

log "Configuring tunnel routes to localhost:${SERVICE_PORT}..."
$SSH_CMD "
sudo cat > /etc/cloudflared/${TUNNEL_UUID}.json << 'JSONEOF'
{
  \"credentials\": \"/etc/cloudflared/${TUNNEL_UUID}.pem\",
  \"url\": \"http://localhost:${SERVICE_PORT}\",
  \"protocol\": \"auto\"
}
JSONEOF
"

# ── Step 4: Start and enable service ───────────────────────

log "Starting cloudflared service..."
$SSH_CMD "
sudo cloudflared service install ${TUNNEL_UUID}
sudo systemctl start cloudflared
sudo systemctl is-active cloudflared
"

# ── Step 5: Route DNS to tunnel ───────────────────────────

log "Routing ${CLOUDFLARE_DOMAIN} to tunnel..."
$SSH_CMD "sudo cloudflared tunnels route dns ${TUNNEL_UUID} ${CLOUDFLARE_DOMAIN}" || {
    warn "DNS routing failed. This may be because the record already exists."
    warn "You can also route manually: ssh sumopod 'sudo cloudflared tunnels route dns ${TUNNEL_UUID} ${CLOUDFLARE_DOMAIN}'"
}

# ── Step 6: Verify connectivity ────────────────────────────

log "Verifying tunnel connection..."
sleep 3
STATUS=$($SSH_CMD "sudo cloudflared tunnels status 2>&1" || true)
if echo "$STATUS" | grep -q "healthy\|running"; then
    log "Tunnel is healthy and connected!"
else
    warn "Tunnel may still be connecting. Check logs:"
    warn "  ssh sumopod 'sudo journalctl -u cloudflared -n 10'"
fi

echo ""

# ── Output summary ─────────────────────────────────────────

timer_print

echo "=========================================="
echo "  Tunnel Setup Complete!"
echo "=========================================="
echo ""
log "Tunnel created: ${TUNNEL_NAME} (${TUNNEL_UUID})"
log "Route: ${CLOUDFLARE_DOMAIN} → http://localhost:${SERVICE_PORT}"
echo ""
echo "  Test: curl -I https://${CLOUDFLARE_DOMAIN}"
echo ""
echo "  Troubleshooting:"
echo "    View logs:   ssh sumopod 'sudo journalctl -u cloudflared -f'"
echo "    Restart:     ssh sumopod 'sudo systemctl restart cloudflared'"
echo "    Status:      ssh sumopod 'sudo cloudflared tunnels status'"
