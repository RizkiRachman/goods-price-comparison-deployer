#!/bin/bash
# Persistent SSH tunnel to VPS backend via autossh
# Forwards a local port to the backend service running on VPS (localhost:8080)
# Uses autossh for auto-reconnection on network drops
#
# Usage:
#   ./helpers/port-forward.sh               # Start tunnel (default localhost:8080)
#   ./helpers/port-forward.sh -p 9090        # Forward to local port 9090
#   ./helpers/port-forward.sh -k             # Kill existing tunnel
#   ./helpers/port-forward.sh -s             # Show tunnel status
#   ./helpers/port-forward.sh -m             # Monitor mode (continuous status)
#
# Prerequisites:
#   - autossh installed locally (brew install autossh)
#   - VPS accessible via SSH alias "vps" or VPS_HOST env var

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib/common.sh"

# ── Configuration ──────────────────────────────────────────

VPS_USER="${VPS_USER:-ubuntu}"
VPS_SSH_KEY="${VPS_SSH_KEY:-$HOME/.ssh/vps-vps}"

if [ -n "${VPS_HOST:-}" ]; then
    SSH_DEST="${VPS_USER}@${VPS_HOST}"
else
    SSH_DEST="vps"
fi

LOCAL_PORT="${LOCAL_PORT:-8080}"
REMOTE_HOST="${REMOTE_HOST:-localhost}"
REMOTE_PORT="${REMOTE_PORT:-8080}"
TUNNEL_NAME="port-forward"
PID_FILE="/tmp/${TUNNEL_NAME}.pid"

# ── Functions ──────────────────────────────────────────────

start_tunnel() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        log "Tunnel already running (PID $(cat "$PID_FILE")). Use -k to kill first, or -s to check status."
        exit 1
    fi

    stage "BE Tunnel — autossh"
    log "SSH destination: ${SSH_DEST}"
    log "Forwarding:      localhost:${LOCAL_PORT} → ${REMOTE_HOST}:${REMOTE_PORT}"
    log "Auto-reconnect:  enabled (autossh)"
    echo ""

    autossh -M 0 \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -o "ExitOnForwardFailure=yes" \
        -o "StrictHostKeyChecking=no" \
        ${VPS_SSH_KEY:+-i "$VPS_SSH_KEY"} \
        -NTL "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" \
        "${SSH_DEST}" &

    TUNNEL_PID=$!
    echo "$TUNNEL_PID" > "$PID_FILE"

    sleep 2
    if kill -0 "$TUNNEL_PID" 2>/dev/null; then
        log "Tunnel started (PID ${TUNNEL_PID})"
        log "Test: curl -s http://localhost:${LOCAL_PORT}/v1/actuator/health"
    else
        error "Failed to start tunnel. Check SSH connectivity to ${SSH_DEST}"
    fi
}

kill_tunnel() {
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            log "Killed tunnel (PID ${OLD_PID})"
        fi
        rm -f "$PID_FILE"
    fi
    pkill -f "autossh.*${TUNNEL_NAME}" 2>/dev/null || true
    pkill -f "ssh.*-NTL.*${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" 2>/dev/null || true
    log "All tunnel processes cleaned"
}

status_tunnel() {
    echo ""
    stage "BE Tunnel — Status"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        PID=$(cat "$PID_FILE")
        log "PID:       ${PID}"
        log "Forward:   localhost:${LOCAL_PORT} → ${REMOTE_HOST}:${REMOTE_PORT}"
        log "Target:    ${SSH_DEST}"
        log "Uptime:    $(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')"
        echo ""
        log "Testing connection..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "http://localhost:${LOCAL_PORT}/v1/actuator/health" 2>/dev/null || echo "failed")
        if [ "$HTTP_CODE" = "200" ]; then
            log "Backend: reachable (HTTP ${HTTP_CODE})"
        else
            warn "Backend: HTTP ${HTTP_CODE} (may still be initializing)"
        fi
    else
        warn "Tunnel is not running"
    fi
    echo ""
    log "To start: ./helpers/port-forward.sh"
}

monitor_tunnel() {
    log "Monitoring tunnel (Ctrl+C to stop)..."
    echo ""
    while true; do
        clear 2>/dev/null || true
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            PID=$(cat "$PID_FILE")
            echo "  BE Tunnel:  ACTIVE (PID ${PID})"
            echo "  Forward:    localhost:${LOCAL_PORT} → ${REMOTE_HOST}:${REMOTE_PORT}"
            echo "  Target:     ${SSH_DEST}"
            echo "  Uptime:     $(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ')"

            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
                "http://localhost:${LOCAL_PORT}/v1/actuator/health" 2>/dev/null || echo "?")
            if [ "$HTTP_CODE" = "200" ]; then
                echo "  Backend:    OK (HTTP ${HTTP_CODE})"
            else
                echo "  Backend:    HTTP ${HTTP_CODE}"
            fi
        else
            echo "  BE Tunnel:  STOPPED"
        fi
        echo ""
        echo "  Refreshing every 5s..."
        sleep 5
    done
}

# ── CLI ────────────────────────────────────────────────────

usage() {
    cat <<'HELP'
Usage: port-forward.sh [OPTIONS]

Persistent SSH tunnel to VPS backend via autossh.

Options:
  -p PORT    Local port to forward (default: 8080)
  -k         Kill existing tunnel
  -s         Show tunnel status
  -m         Monitor mode (continuous status refresh)
  -h         This help

Environment variables:
  VPS_HOST        VPS IP/hostname (default: uses SSH alias "vps")
  VPS_USER        SSH user (default: ubuntu)
  VPS_SSH_KEY     SSH key path (default: ~/.ssh/vps-vps)
  LOCAL_PORT      Local port override (default: 8080)
  REMOTE_HOST     Remote host on VPS (default: localhost)
  REMOTE_PORT     Remote port on VPS (default: 8080)
HELP
    exit 0
}

while getopts "p:ksmh" opt; do
    case $opt in
        p) LOCAL_PORT="$OPTARG" ;;
        k) kill_tunnel; exit 0 ;;
        s) status_tunnel; exit 0 ;;
        m) monitor_tunnel; exit 0 ;;
        h) usage ;;
        *) usage ;;
    esac
done

start_tunnel
