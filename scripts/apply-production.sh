#!/bin/bash
# Apply Production: execute the full CI/CD pipeline using external database.
# Uses DATABASE_HOST (falls back to POSTGRES_HOST if not set).
# Assumes infrastructure is already initialized (run ./scripts/init.sh first).
#
# Usage: ./scripts/apply-production.sh
#
# Environment:
#   Set DATABASE_HOST and DATABASE_PORT in .env for external database.
#   If not set, defaults to POSTGRES_HOST/POSTGRES_PORT (local dev).

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
echo "  APPLY — Production CI/CD Pipeline"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Image:   ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  DB Host: ${DATABASE_HOST} (source: ${DATABASE_HOST:+external}${DATABASE_HOST:-local POSTGRES_HOST})"
echo "  DB Port: ${DATABASE_PORT}"
echo ""

timer_start
stage_production_pipeline_run

echo ""
echo "=========================================="
echo "  APPLY PRODUCTION COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAMESPACE}/${DEPLOYMENT_NAME}"
echo "  Image:   ${REGISTRY_CLUSTER_HOST}:${REGISTRY_CLUSTER_PORT}/${IMAGE_NAME}:${IMAGE_TAG}"
echo "  DB Host: ${DATABASE_HOST}"
echo ""
