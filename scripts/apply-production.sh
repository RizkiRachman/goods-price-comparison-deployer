#!/bin/bash
# Apply Production: execute the full CI/CD pipeline with VPS SSH deploy.
# This is a convenience wrapper around ./scripts/apply.sh --production.
#
# Usage: ./scripts/apply-production.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/apply.sh" --production
