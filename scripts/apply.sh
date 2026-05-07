#!/bin/bash
# Apply: execute the full CI/CD pipeline (clone → build → test → image → db → deploy).
# Assumes infrastructure is already initialized (run ./scripts/init.sh first).
#
# Usage: ./scripts/apply.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/k8s.sh"
source "$SCRIPT_DIR/stages/pipeline-run.sh"

load_env
set_defaults
check_prerequisites
check_tekton_pipeline

sync_host_endpoints

echo ""
echo "=========================================="
echo "  APPLY — Full CI/CD Pipeline"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Image:   ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

timer_start
stage_pipeline_run

echo ""
echo "=========================================="
echo "  APPLY COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAMESPACE}/${DEPLOYMENT_NAME}"
echo "  Image:   ${REGISTRY_CLUSTER_HOST}:${REGISTRY_CLUSTER_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
