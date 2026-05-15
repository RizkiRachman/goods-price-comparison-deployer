#!/bin/bash
# Manage the frontend dashboard on Sumopod VPS
#
# Usage:
#   ./helpers/dashboard.sh status       # Check service status
#   ./helpers/dashboard.sh logs         # Tail logs
#   ./helpers/dashboard.sh logs -n 50   # Last 50 lines
#   ./helpers/dashboard.sh restart      # Restart the service
#   ./helpers/dashboard.sh stop         # Stop the service
#   ./helpers/dashboard.sh start        # Start the service
#   ./helpers/dashboard.sh build        # Rebuild the frontend (npm run build)
#   ./helpers/dashboard.sh deploy       # Full: git pull → build → restart

set -euo pipefail

SSH_DEST="vps"
APP_DIR="goods-price-comparison-dashboard"
SERVICE="goods-price-dashboard"

case "${1:-status}" in
    status)
        echo "=== Dashboard Service ==="
        ssh "$SSH_DEST" "sudo systemctl status $SERVICE --no-pager"
        echo ""
        echo "=== Caddy Domain ==="
        ssh "$SSH_DEST" "sudo grep -E '^aneh\.biz\.id|www\.' /etc/caddy/Caddyfile"
        ;;
    logs)
        shift
        EXTRA_ARGS="${*:--f}"
        echo "Tailing logs for: $SERVICE"
        ssh "$SSH_DEST" "sudo journalctl -u $SERVICE $EXTRA_ARGS --no-pager"
        ;;
    restart)
        echo "Restarting $SERVICE..."
        ssh "$SSH_DEST" "sudo systemctl restart $SERVICE && echo 'Done'"
        ;;
    stop)
        echo "Stopping $SERVICE..."
        ssh "$SSH_DEST" "sudo systemctl stop $SERVICE && echo 'Done'"
        ;;
    start)
        echo "Starting $SERVICE..."
        ssh "$SSH_DEST" "sudo systemctl start $SERVICE && echo 'Done'"
        ;;
    build)
        echo "Building frontend on VPS..."
        ssh "$SSH_DEST" "cd ~/$APP_DIR && npm run build 2>&1"
        echo "Build complete."
        ;;
    deploy)
        echo "=== Deploying Frontend ==="
        echo "[1/3] Pulling latest code..."
        ssh "$SSH_DEST" "cd ~/$APP_DIR && git pull 2>&1"
        echo "[2/3] Building..."
        ssh "$SSH_DEST" "cd ~/$APP_DIR && npm run build 2>&1"
        echo "[3/3] Restarting service..."
        ssh "$SSH_DEST" "sudo systemctl restart $SERVICE && echo 'Done'"
        echo "=== Deploy complete ==="
        ;;
    -h|--help|help)
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  status              Check service status (default)"
        echo "  logs [args]         Tail logs (default: -f)"
        echo "  restart             Restart the service"
        echo "  stop                Stop the service"
        echo "  start               Start the service"
        echo "  build               Rebuild the frontend"
        echo "  deploy              Full: git pull → build → restart"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Usage: $0 {status|logs|restart|stop|start|build|deploy}"
        exit 1
        ;;
esac
