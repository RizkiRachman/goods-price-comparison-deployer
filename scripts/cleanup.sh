#!/bin/bash
# Clean up service-specific Tekton resources
# Does NOT delete shared infrastructure (namespace, SA, RBAC, registry secret)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYER_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log()   { echo -e "${GREEN}[INFO]${NC} $1"; }

# Load environment
if [ -f "$DEPLOYER_DIR/.env" ]; then
    set -a && source "$DEPLOYER_DIR/.env" && set +a
fi

PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-goods-price-service}"

warn "This will delete service-specific Tekton resources in namespace: ${PIPELINE_NAMESPACE}"
warn "Shared infrastructure (SA, RBAC, registry secret) will NOT be deleted."
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

log "Deleting PipelineRuns..."
kubectl delete pipelineruns -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipeline=goods-price-pipeline 2>/dev/null || true

log "Deleting TaskRuns..."
kubectl delete taskruns -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipeline=goods-price-pipeline 2>/dev/null || true

log "Deleting Pipeline..."
kubectl delete pipeline goods-price-pipeline -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting Tasks..."
kubectl delete task cleanup maven-build maven-test docker-build deploy -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting PVCs..."
kubectl delete pvc "${DEPLOYMENT_NAME}-pvc" maven-cache-pvc -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting service-specific secrets..."
kubectl delete secret github-maven-credentials maven-settings-secret -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting service RBAC..."
kubectl delete rolebinding "${DEPLOYMENT_NAME}-binding" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true
kubectl delete role "${DEPLOYMENT_NAME}-role" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log ""
log "✅ Service resources cleaned up!"
log "Shared infrastructure is still running in namespace: $PIPELINE_NAMESPACE"
