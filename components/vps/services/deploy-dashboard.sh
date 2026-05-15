#!/bin/bash
# Deploy goods-price-comparison-dashboard to VPS
# Pulls latest code, builds with npm, restarts systemd service
#
# Usage:
#   ./vps/services/deploy-dashboard.sh
#
# Optional env vars:
#   VPS_HOST           — VPS IP or hostname (default: uses SSH alias "vps")
#   APP_DIR            — Dashboard directory on VPS (default: /home/ubuntu/goods-price-comparison-dashboard)
#   SERVICE            — Systemd service name (default: goods-price-comparison-dashboard)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/lib/common.sh"

# ── Configuration ──────────────────────────────────────────

VPS_USER="${VPS_USER:-ubuntu}"
VPS_SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/vps-vps}"

if [ -n "${VPS_HOST:-}" ]; then
    SSH_DEST="${VPS_USER}@${VPS_HOST}"
    SSH_CMD="ssh -i ${VPS_SSH_KEY} -o StrictHostKeyChecking=no ${SSH_DEST}"
else
    SSH_DEST="vps"
    SSH_CMD="ssh -o StrictHostKeyChecking=no ${SSH_DEST}"
fi

APP_DIR="${APP_DIR:-/home/ubuntu/goods-price-comparison-dashboard}"
SERVICE="${SERVICE:-goods-price-dashboard}"

# ── Deploy Steps ───────────────────────────────────────────

timer_start

echo ""
echo "=================================================="
echo "  Deploy Dashboard to VPS: ${SSH_DEST}"
echo "=================================================="
echo ""

stage "Pull latest code"
step "Pulling from git in ${APP_DIR}..."
$SSH_CMD "cd ${APP_DIR} && git pull" || error "Git pull failed"
log "Code updated"

echo ""

stage "Install dependencies"
step "Running npm install..."
$SSH_CMD "cd ${APP_DIR} && npm install" || error "npm install failed"
log "Dependencies installed"

echo ""

stage "Build"
step "Running npm run build..."
$SSH_CMD "cd ${APP_DIR} && npm run build" || error "npm run build failed"
log "Build complete"

echo ""

stage "Restart service"
step "Restarting ${SERVICE}..."
$SSH_CMD "sudo systemctl restart ${SERVICE}" || error "Failed to restart ${SERVICE}"

sleep 3

ACTIVE=$($SSH_CMD "sudo systemctl is-active ${SERVICE}" 2>/dev/null || echo "inactive")
if [ "$ACTIVE" = "active" ]; then
    log "Service ${SERVICE} is active"
else
    warn "Service is ${ACTIVE}. Checking logs..."
    $SSH_CMD "sudo journalctl -u ${SERVICE} -n 20 --no-pager"
fi

echo ""

timer_print
echo ""
echo "=================================================="
echo "  ✅ Dashboard deploy complete!"
echo "=================================================="
