#!/bin/bash
# Apply: execute the full CI/CD pipeline (clone → build → test → image → db → deploy).
# Assumes infrastructure is already initialized (run ./scripts/init.sh first).
#
# Usage: ./scripts/apply.sh            # Local mode (default): build + push to local registry
#        ./scripts/apply.sh --cloud    # Cloud mode: skip build, deploy from GHCR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/k8s.sh"
source "$SCRIPT_DIR/stages/pipeline-run.sh"

PIPELINE_MODE="local"
if [ "${1:-}" = "--cloud" ]; then
    PIPELINE_MODE="cloud"
fi
export PIPELINE_MODE

load_env
set_defaults
check_prerequisites
check_tekton_pipeline

sync_host_endpoints

if [ "$PIPELINE_MODE" = "cloud" ]; then
    IMAGE_REF="ghcr.io/${GHCR_OWNER}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    IMAGE_REF="${REGISTRY_CLUSTER_HOST:-k3d-dev-infra-registry}:${REGISTRY_CLUSTER_PORT:-5000}/${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo ""
echo "=========================================="
echo "  APPLY — CI/CD Pipeline"
echo "=========================================="
echo ""
echo "  Mode:    ${PIPELINE_MODE}"
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Image:   ${IMAGE_REF}"
echo ""

timer_start
stage_pipeline_run

echo ""
echo "=========================================="
echo "  APPLY COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAMESPACE}/${DEPLOYMENT_NAME}"
echo "  Image:   ${IMAGE_REF}"
echo ""
