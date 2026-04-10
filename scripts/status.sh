#!/bin/bash
# Check the status of Tekton resources for this service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYER_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Load environment
if [ -f "$DEPLOYER_DIR/.env" ]; then
    set -a && source "$DEPLOYER_DIR/.env" && set +a
fi

PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"

log "=== Goods-Price Service - Tekton Status ==="
log "Namespace: ${PIPELINE_NAMESPACE}"
log ""

log "--- Tasks ---"
kubectl get tasks -n "$PIPELINE_NAMESPACE" 2>/dev/null || warn "No tasks found"

log ""
log "--- Pipelines ---"
kubectl get pipelines -n "$PIPELINE_NAMESPACE" 2>/dev/null || warn "No pipelines found"

log ""
log "--- PipelineRuns ---"
kubectl get pipelineruns -n "$PIPELINE_NAMESPACE" 2>/dev/null || warn "No pipelineruns found"

log ""
log "--- TaskRuns ---"
kubectl get taskruns -n "$PIPELINE_NAMESPACE" 2>/dev/null || warn "No taskruns found"

log ""
log "--- Pods ---"
kubectl get pods -n "$PIPELINE_NAMESPACE" 2>/dev/null || warn "No pods found"

log ""
log "--- PVCs ---"
kubectl get pvc -n "$PIPELINE_NAMESPACE" 2>/dev/null || warn "No PVCs found"
