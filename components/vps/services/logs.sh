#!/bin/bash
# Tail application logs from the Sumopod VPS via SSH
#
# Usage:
#   ./helpers/logs.sh                    # Live tail (-f)
#   ./helpers/logs.sh -n 50              # Last 50 lines
#   ./helpers/logs.sh --since "30m"      # Last 30 minutes
#   ./helpers/logs.sh --since today      # Today's logs
#   ./helpers/logs.sh -p err             # Error level only
#   ./helpers/logs.sh --caddy            # Tail Caddy logs instead
#   ./helpers/logs.sh --service goods-price-service  # Custom service name

set -euo pipefail

SSH_DEST="vps-root"
SERVICE="goods-price-service"
EXTRA_ARGS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --caddy)
            SERVICE="caddy"
            shift
            ;;
        --service)
            SERVICE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options] [journalctl-args]"
            echo ""
            echo "Options:"
            echo "  --caddy              Tail Caddy reverse proxy logs"
            echo "  --service <name>     Tail a specific systemd service (default: goods-price-service)"
            echo "  -h, --help           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                   # Live tail app logs"
            echo "  $0 -n 50             # Last 50 lines"
            echo "  $0 --since \"30m\"     # Last 30 minutes"
            echo "  $0 --since today     # Today's logs"
            echo "  $0 -p err            # Error level only"
            echo "  $0 --caddy           # Live tail Caddy logs"
            exit 0
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

# Default to follow mode if no journalctl args provided
if [[ -z "${EXTRA_ARGS}" ]]; then
    EXTRA_ARGS="-f"
fi

echo "Tailing logs for: $SERVICE"
echo "Host: $SSH_DEST"
echo "---"
ssh -q "$SSH_DEST" "journalctl -u $SERVICE $EXTRA_ARGS --no-pager"
