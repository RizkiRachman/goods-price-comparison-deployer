#!/bin/bash
# Trigger a PipelineRun for the goods-price pipeline

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYER_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Load environment
if [ -f "$DEPLOYER_DIR/.env" ]; then
    set -a && source "$DEPLOYER_DIR/.env" && set +a
else
    error ".env file not found. Copy .env.template to .env and configure it."
fi

PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
RUN_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAME} ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH} ${IMAGE_NAME} ${IMAGE_TAG} ${REGISTRY_CLUSTER_HOST} ${REGISTRY_CLUSTER_PORT} ${DEPLOYMENT_NAMESPACE}'

log "Creating PipelineRun in namespace: ${PIPELINE_NAMESPACE}"

# Create PipelineRun (uses generateName, so kubectl create is required)
envsubst "$RUN_VARS" < "$DEPLOYER_DIR/pipelines/pipeline-run.yaml" | kubectl create -f - -n "$PIPELINE_NAMESPACE"

log "✅ PipelineRun created!"
log ""
log "To check status:"
log "  kubectl get pipelineruns -n ${PIPELINE_NAMESPACE}"
log ""
log "To view logs:"
log "  tkn pipelinerun logs -f -n ${PIPELINE_NAMESPACE} <pipeline-run-name>"
log ""
log "Or use the Tekton Dashboard at http://localhost:9097"
