#!/bin/bash
# Debug and test the Caddy reverse proxy + Cloudflare Tunnel setup
#
# Caddy runs behind Cloudflare Tunnel. No TLS on VPS side —
# tunnel terminates TLS at Cloudflare Edge.
#
# Usage:
#   ./ops/caddy.sh status       # Check Caddy + tunnel status
#   ./ops/caddy.sh logs         # Tail Caddy logs (follow)
#   ./ops/caddy.sh logs -n 50   # Last 50 lines
#   ./ops/caddy.sh restart      # Restart Caddy
#   ./ops/caddy.sh test         # Test aneh.biz.id from local
#   ./ops/caddy.sh dig          # Check DNS (CNAME to tunnel)
#   ./ops/caddy.sh help         # Show this help

set -euo pipefail

SSH_DEST="vps-root"
DOMAIN="aneh.biz.id"
API_HEALTH_PATH="actuator/health"

# Run a command on the VPS (root user, no sudo needed)
ssh_cmd() {
  ssh -q "$SSH_DEST" "$*"
}

case "${1:-status}" in
    status)
        echo "=== Caddy Service ==="
        ssh_cmd systemctl status caddy --no-pager | head -15
        echo ""
        echo "=== Caddy Config ==="
        ssh_cmd cat /etc/caddy/Caddyfile
        echo ""
        echo "=== Listening Ports ==="
        ssh_cmd ss -tlnp | grep -E '80|8080|5173'
        echo ""
        echo "=== Tunnel Status ==="
        ssh_cmd systemctl status cloudflared --no-pager | head -10

        ;;
    logs)
        shift
        EXTRA_ARGS="${*:--f}"
        echo "Tailing Caddy logs..."
        ssh_cmd journalctl -u caddy "$EXTRA_ARGS" --no-pager
        ;;
    restart)
        echo "Restarting Caddy..."
        ssh_cmd systemctl restart caddy && echo 'Done'
        echo ""
        sleep 2
        ssh_cmd systemctl is-active caddy
        ;;
    test)
        echo "=== Testing $DOMAIN from local ==="
        echo ""
        echo "Frontend:"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 15 "https://$DOMAIN/" 2>/dev/null || echo "FAILED")
        echo "  HTTP $HTTP_CODE"
        if [ "$HTTP_CODE" = "200" ]; then
            echo "  ✅ Frontend reachable"
        else
            echo "  ❌ Frontend not reachable"
        fi

        echo ""
        echo "API health:"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 15 "https://$DOMAIN/$API_HEALTH_PATH" 2>/dev/null || echo "FAILED")
        echo "  HTTP $HTTP_CODE"

        echo ""
        echo "SSL (Cloudflare Edge):"
        curl -svI --connect-timeout 15 "https://$DOMAIN" 2>&1 | grep -i "subject:\|issuer:\|SSL certificate\|TLS handshake" || echo "  SSL info not available"
        ;;
    dig)
        echo "=== DNS Records ==="
        echo ""
        echo "CNAME for $DOMAIN (tunnel endpoint):"
        dig "$DOMAIN" CNAME +short @1.1.1.1
        echo ""
        echo "Nameservers for $DOMAIN:"
        dig NS "$DOMAIN" +short @1.1.1.1
        echo ""
        echo "Cloudflare proxy status:"
        dig "$DOMAIN" +short | head -1 | grep -q '^104\.\|^172\.' && echo "  ☁️  Proxied (Cloudflare IP)" || echo "  🔴 Not proxied"
        ;;
    -h|--help|help)
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  status              Check Caddy + tunnel status (default)"
        echo "  logs [args]         Tail Caddy logs (default: -f)"
        echo "  restart             Restart Caddy"
        echo "  test                Test aneh.biz.id from local machine"
        echo "  dig                 Check DNS (CNAME to tunnel endpoint)"
        echo ""
        echo "Architecture:"
        echo "  aneh.biz.id → Cloudflare Tunnel → localhost:80 (Caddy)"
        echo "    Caddy: /v1/* → proxy → localhost:8080 (backend)"
        echo "           /*    → serve dist/  (dashboard FE)"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Usage: $0 {status|logs|restart|test|dig}"
        exit 1
        ;;
esac
