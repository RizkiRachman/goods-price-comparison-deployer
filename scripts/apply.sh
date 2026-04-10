#!/bin/bash
# Apply service-specific Tekton resources to the shared dev-infrastructure cluster
# Assumes dev-infrastructure is already running (k3d cluster, Tekton, SA, RBAC, registry secret)
#
# Uses envsubst with EXPLICIT variable lists to preserve Tekton's $(...) syntax.
# Only the listed ${VARS} are substituted; $(workspaces.*.path) and $(params.*) remain intact.

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

# Set defaults for optional variables
PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
DEPLOYMENT_NAMESPACE="${DEPLOYMENT_NAMESPACE:-tekton-pipelines}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-goods-price-service}"
DEPLOYMENT_PORT="${DEPLOYMENT_PORT:-8080}"
KUBECTL_IMAGE="${KUBECTL_IMAGE:-bitnami/kubectl:latest}"
MAVEN_IMAGE="${MAVEN_IMAGE:-maven:3.9-eclipse-temurin-17}"
KANIKO_IMAGE="${KANIKO_IMAGE:-gcr.io/kaniko-project/executor:latest}"
REGISTRY_CLUSTER_HOST="${REGISTRY_CLUSTER_HOST:-k3d-dev-infra-registry}"
REGISTRY_CLUSTER_PORT="${REGISTRY_CLUSTER_PORT:-5000}"
RBAC_USER="${RBAC_USER:-goods-price-service}"

K8S_SETUP_DIR="$DEPLOYER_DIR/k8s-setup"
TASKS_DIR="$DEPLOYER_DIR/tasks"
PIPELINES_DIR="$DEPLOYER_DIR/pipelines"
PVC_DIR="$DEPLOYER_DIR/pvc"

# envsubst variable lists — only substitute these, leave Tekton $(...) untouched
TASK_VARS='${PIPELINE_NAMESPACE} ${KUBECTL_IMAGE} ${MAVEN_IMAGE} ${KANIKO_IMAGE} ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT}'
PIPELINE_VARS='${PIPELINE_NAMESPACE} ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH} ${IMAGE_NAME} ${IMAGE_TAG} ${REGISTRY_CLUSTER_HOST} ${REGISTRY_CLUSTER_PORT} ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME}'
PVC_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAME}'
RBAC_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAME} ${RBAC_USER}'

# Prerequisite checks
log "Checking prerequisites..."
if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster. Start dev-infrastructure first."
fi

if ! kubectl get namespace "$PIPELINE_NAMESPACE" &>/dev/null; then
    error "Namespace '$PIPELINE_NAMESPACE' not found. Run dev-infrastructure setup first."
fi

if ! kubectl get crd tasks.tekton.dev &>/dev/null; then
    error "Tekton Pipelines not installed. Run dev-infrastructure setup first."
fi

log "Prerequisites check passed."

# Apply RBAC — scoped Role + RoleBinding for this service
log "Applying service RBAC..."
if [ -f "$K8S_SETUP_DIR/rbac-role.yaml" ]; then
    envsubst "$RBAC_VARS" < "$K8S_SETUP_DIR/rbac-role.yaml" | kubectl apply -f - && log "  Applied: rbac-role.yaml" || warn "  Failed: rbac-role.yaml"
fi
if [ -f "$K8S_SETUP_DIR/rbac-rolebinding.yaml" ]; then
    envsubst "$RBAC_VARS" < "$K8S_SETUP_DIR/rbac-rolebinding.yaml" | kubectl apply -f - && log "  Applied: rbac-rolebinding.yaml (user: $RBAC_USER)" || warn "  Failed: rbac-rolebinding.yaml"
fi

# Apply PVCs
log "Applying PVCs..."
for pvc in "$PVC_DIR"/*.yaml; do
    if [ -f "$pvc" ]; then
        envsubst "$PVC_VARS" < "$pvc" | kubectl apply -f - && log "  Applied: $(basename "$pvc")" || warn "  Failed: $(basename "$pvc")"
    fi
done

# Create GitHub Maven credentials secret if it doesn't exist
log "Creating github-maven-credentials secret..."
if ! kubectl get secret github-maven-credentials -n "$PIPELINE_NAMESPACE" &>/dev/null; then
    if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_TOKEN" ]; then
        kubectl create secret generic github-maven-credentials \
            --from-literal=username="$GITHUB_USERNAME" \
            --from-literal=token="$GITHUB_TOKEN" \
            -n "$PIPELINE_NAMESPACE"
        log "  Created github-maven-credentials secret"
    else
        warn "GITHUB_USERNAME or GITHUB_TOKEN not set in .env"
        warn "  Create manually: kubectl create secret generic github-maven-credentials --from-literal=username=<user> --from-literal=token=<token> -n $PIPELINE_NAMESPACE"
    fi
else
    log "  github-maven-credentials secret already exists"
fi

# Create maven-settings-secret from github-maven-credentials
log "Creating maven-settings-secret..."
if [ -f "$SCRIPT_DIR/create-maven-settings-secret.sh" ]; then
    "$SCRIPT_DIR/create-maven-settings-secret.sh" || warn "Failed to create maven-settings-secret"
else
    warn "create-maven-settings-secret.sh not found, skipping"
fi

# Install git-clone task from Tekton catalog
log "Installing git-clone task from Tekton catalog..."
kubectl apply -n "$PIPELINE_NAMESPACE" -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml 2>/dev/null || warn "Failed to install git-clone task (may already exist)"

# Apply tasks
log "Applying service-specific tasks..."
for task in "$TASKS_DIR"/*.yaml; do
    if [ -f "$task" ]; then
        envsubst "$TASK_VARS" < "$task" | kubectl apply -f - && log "  Applied: $(basename "$task")" || warn "  Failed: $(basename "$task")"
    fi
done

# Apply pipeline (skip pipeline-run files as they use generateName)
log "Applying pipeline..."
for pipeline in "$PIPELINES_DIR"/*.yaml; do
    if [ -f "$pipeline" ]; then
        if [[ "$(basename "$pipeline")" == *pipeline-run* ]]; then
            log "  Skipping: $(basename "$pipeline") (use run-pipeline.sh to create)"
            continue
        fi
        envsubst "$PIPELINE_VARS" < "$pipeline" | kubectl apply -f - && log "  Applied: $(basename "$pipeline")" || warn "  Failed: $(basename "$pipeline")"
    fi
done

log ""
log "✅ Service resources applied successfully!"
log ""
log "To run the pipeline:"
log "  ./scripts/run-pipeline.sh"
