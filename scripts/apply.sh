#!/bin/bash
# Apply: Execute full Tekton pipeline (clone → build → test → image → deploy)
# Assumes infrastructure is already initialized (run ./scripts/init.sh first)
#
# Usage: ./scripts/apply.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib + stages
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/stages/pipeline-run.sh"

load_env
set_defaults
check_prerequisites
check_tekton_pipeline

echo ""
echo "=========================================="
echo "  APPLY — Full Pipeline Execution"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Image:   ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Mode:    full (all tasks including deploy)"
echo ""

timer_start

stage_pipeline_run "full"

echo ""
echo "=========================================="
echo "  ✅ APPLY COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAMESPACE}/${DEPLOYMENT_NAME}"
echo "  Image:   ${REGISTRY_CLUSTER_HOST}:${REGISTRY_CLUSTER_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
