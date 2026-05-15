#!/bin/bash
# Apply: execute the full CI/CD pipeline (clone → build → test → image → db → deploy).
# Assumes infrastructure is already initialized (run ./installation/init.sh first).
#
# Usage: ./scripts/apply.sh                # Local mode (default): build + push to local registry + K8s deploy
#        ./scripts/apply.sh --production   # Production mode: CI + VPS SSH deploy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/k8s.sh"
source "$SCRIPT_DIR/stages/pipeline-run.sh"

PIPELINE_MODE="local"
if [ "${1:-}" = "--production" ]; then
    PIPELINE_MODE="production"
fi
export PIPELINE_MODE

load_env
set_defaults

# Force mode-specific values (overrides .env / .env.production)
if [ "$PIPELINE_MODE" = "production" ]; then
    ENVIRONMENT_NAME="production"
    COMPONENT_MOUNT="production/component"
    INFRA_DB_MOUNT="production/infrastructure"
fi

# Explicitly export key variables so envsubst picks them up
export COMPONENT_MOUNT COMPONENT_NAME INFRA_DB_MOUNT ENVIRONMENT_NAME DATABASE_HOST DATABASE_PORT

echo ""
echo "━━━ Environment Check ━━━"
echo "  PIPELINE_MODE:    ${PIPELINE_MODE}"
echo "  COMPONENT_MOUNT:  ${COMPONENT_MOUNT}"
echo "  COMPONENT_NAME:   ${COMPONENT_NAME}"
echo "  INFRA_DB_MOUNT:   ${INFRA_DB_MOUNT}"
echo "  ENVIRONMENT_NAME: ${ENVIRONMENT_NAME}"
echo ""

check_prerequisites

check_tekton_pipeline

sync_host_endpoints

IMAGE_REF="${REGISTRY_CLUSTER_HOST:-k3d-dev-infra-registry}:${REGISTRY_CLUSTER_PORT:-5000}/${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "=========================================="
echo "  APPLY — CI/CD Pipeline"
echo "=========================================="
echo ""
echo "  Mode:    ${PIPELINE_MODE}"
echo "  Service: ${DEPLOYMENT_NAME}"
if [ "$PIPELINE_MODE" = "production" ]; then
    echo "  Deploy:  VPS (deploy@43.129.38.221)"
else
    echo "  Image:   ${IMAGE_REF}"
fi
echo ""

timer_start
stage_pipeline_run

echo ""
echo "=========================================="
echo "  APPLY COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
