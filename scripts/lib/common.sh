#!/bin/bash
# Common utilities: logging, spinner, timer, environment, checks, K8s resource application

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$_LIB_DIR")"
DEPLOYER_DIR="$(dirname "$SCRIPTS_DIR")"
TERRAFORM_DIR="$DEPLOYER_DIR/terraform"

# ── Logging ───────────────────────────────────────────────

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
stage() { echo -e "\n${CYAN}${BOLD}━━━ STAGE: $1 ━━━${NC}"; }
step()  { echo -e "  ${DIM}→${NC} $1"; }

# ── Progress Spinner ──────────────────────────────────────

_SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spin_until() {
    local desc="$1"
    local pid="$2"
    local i=0

    if [ ! -t 1 ]; then
        wait "$pid" 2>/dev/null
        return $?
    fi

    while kill -0 "$pid" 2>/dev/null; do
        local char="${_SPINNER_CHARS:$((i % ${#_SPINNER_CHARS})):1}"
        printf "\r  ${CYAN}%s${NC} %s..." "$char" "$desc"
        sleep 0.1
        i=$((i+1))
    done

    printf "\r  ${GREEN}✓${NC} %s    \n" "$desc"
    wait "$pid" 2>/dev/null
    return $?
}

run_spin() {
    local desc="$1"; shift
    "$@" &>/dev/null &
    local pid=$!
    spin_until "$desc" "$pid"
    return $?
}

# ── Timing ────────────────────────────────────────────────

_timer_start=0

timer_start() {
    _timer_start=$(date +%s)
}

timer_elapsed() {
    local now=$(date +%s)
    local diff=$((now - _timer_start))
    if [ "$diff" -lt 60 ]; then
        echo "${diff}s"
    else
        printf "%dm%ds" $((diff/60)) $((diff%60))
    fi
}

timer_print() {
    echo -e "  ${DIM}⏱ ${NC}$(timer_elapsed)"
}

# ── Environment ───────────────────────────────────────────

load_env() {
    if [ -f "$DEPLOYER_DIR/.env" ]; then
        set -a && source "$DEPLOYER_DIR/.env" && set +a
    else
        warn ".env file not found. Some defaults will be used."
    fi
}

set_defaults() {
    VAULT_ADDRESS_TERRAFORM="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
    DEPLOYMENT_NAMESPACE="${DEPLOYMENT_NAMESPACE:-tekton-pipelines}"
    DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-goods-price-service}"
    DEPLOYMENT_PORT="${DEPLOYMENT_PORT:-8080}"
    KUBECTL_IMAGE="${KUBECTL_IMAGE:-bitnami/kubectl:latest}"
    MAVEN_IMAGE="${MAVEN_IMAGE:-maven:3.9-eclipse-temurin-17}"
    KANIKO_IMAGE="${KANIKO_IMAGE:-gcr.io/kaniko-project/executor:latest}"
    REGISTRY_CLUSTER_HOST="${REGISTRY_CLUSTER_HOST:-k3d-dev-infra-registry}"
    REGISTRY_CLUSTER_PORT="${REGISTRY_CLUSTER_PORT:-5000}"
    REGISTRY_PORT="${REGISTRY_PORT:-5002}"
    RBAC_USER="${RBAC_USER:-goods-price-service}"
    IMAGE_NAME="${IMAGE_NAME:-goods-price-comparison-service}"
    IMAGE_TAG="${IMAGE_TAG:-latest}"
    GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/RizkiRachman/goods-price-comparison-service.git}"
    GIT_REPO_DEFAULT_BRANCH="${GIT_REPO_DEFAULT_BRANCH:-main}"
    PIPELINE_MODE="${PIPELINE_MODE:-full}"

    # Database Provisioning defaults (Vault-based)
    VAULT_ADDRESS_PIPELINE="${VAULT_ADDRESS_PIPELINE:-http://vault-host:8201}"
    INFRA_DB_MOUNT="${INFRA_DB_MOUNT:-local/infrastructure}"
    COMPONENT_MOUNT="${COMPONENT_MOUNT:-local/component}"
    POSTGRES_HOST="${POSTGRES_HOST:-postgres-host}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"
    MIGRATIONS_PATH="${MIGRATIONS_PATH:-src/main/resources/db/migration}"
    COMPONENT_NAME="${COMPONENT_NAME:-${DEPLOYMENT_NAME}}"
}

# ── Prerequisite Checks ──────────────────────────────────

check_prerequisites() {
    log "Checking prerequisites..."
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster. Start dev-infrastructure first."
    fi
    if ! kubectl get namespace "${PIPELINE_NAMESPACE:-tekton-pipelines}" &>/dev/null; then
        error "Namespace '${PIPELINE_NAMESPACE:-tekton-pipelines}' not found. Run dev-infrastructure setup first."
    fi
    log "Prerequisites check passed."
}

check_terraform() {
    if ! command -v terraform &>/dev/null; then
        error "terraform not found. Install Terraform first: https://developer.hashicorp.com/terraform/install"
    fi
}

check_vault() {
    local _vault_addr="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    local _vault_http_code
    _vault_http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${_vault_addr}/v1/sys/health" 2>/dev/null)
    if [[ "$_vault_http_code" =~ ^(200|429|472|473)$ ]]; then
        log "Vault (${_vault_addr}): reachable"
    else
        error "Vault is not reachable at ${_vault_addr} (HTTP ${_vault_http_code:-000}). Start dev-infrastructure first."
    fi
}

check_tekton_pipeline() {
    if ! kubectl get pipeline "${DEPLOYMENT_NAME:-goods-price-service}-pipeline" -n "${PIPELINE_NAMESPACE:-tekton-pipelines}" &>/dev/null; then
        error "Pipeline '${DEPLOYMENT_NAME:-goods-price-service}-pipeline' not found. Run ./scripts/init.sh first."
    fi
}

# ── Health Check ──────────────────────────────────────────

health_check_infra() {
    local PASS=0
    local FAIL=0

    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│         Infrastructure Health Check          │"
    echo "└─────────────────────────────────────────────┘"

    if kubectl cluster-info &>/dev/null; then
        log "  ✅ Kubernetes cluster: reachable"; PASS=$((PASS+1))
    else
        warn "  ❌ Kubernetes cluster: unreachable"; FAIL=$((FAIL+1))
    fi

    if kubectl get namespace "${PIPELINE_NAMESPACE:-tekton-pipelines}" &>/dev/null; then
        log "  ✅ Namespace '${PIPELINE_NAMESPACE:-tekton-pipelines}': exists"; PASS=$((PASS+1))
    else
        warn "  ❌ Namespace '${PIPELINE_NAMESPACE:-tekton-pipelines}': not found"; FAIL=$((FAIL+1))
    fi

    if kubectl get crd tasks.tekton.dev &>/dev/null; then
        log "  ✅ Tekton Pipelines: installed"; PASS=$((PASS+1))
    else
        warn "  ❌ Tekton Pipelines: not installed"; FAIL=$((FAIL+1))
    fi

    local _vault_addr="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    local _vault_http_code
    _vault_http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${_vault_addr}/v1/sys/health" 2>/dev/null)
    # Vault /v1/sys/health returns 200 (active), 429 (standby), 472/473 (DR/perf standby) — all mean reachable
    if [[ "$_vault_http_code" =~ ^(200|429|472|473)$ ]]; then
        log "  ✅ Vault (${_vault_addr}): reachable (HTTP ${_vault_http_code})"; PASS=$((PASS+1))
    else
        warn "  ❌ Vault (${_vault_addr}): unreachable (HTTP ${_vault_http_code:-000})"; FAIL=$((FAIL+1))
    fi

    if curl -sf "http://localhost:${REGISTRY_PORT:-5002}/v2/" &>/dev/null; then
        log "  ✅ Registry (localhost:${REGISTRY_PORT:-5002}): reachable"; PASS=$((PASS+1))
    else
        warn "  ❌ Registry (localhost:${REGISTRY_PORT:-5002}): unreachable"; FAIL=$((FAIL+1))
    fi

    if kubectl get sa tekton-sa -n "${PIPELINE_NAMESPACE:-tekton-pipelines}" &>/dev/null; then
        log "  ✅ ServiceAccount 'tekton-sa': exists"; PASS=$((PASS+1))
    else
        warn "  ❌ ServiceAccount 'tekton-sa': not found"; FAIL=$((FAIL+1))
    fi

    echo ""
    echo "  Results: ${PASS} passed, ${FAIL} failed"
    echo ""

    if [ "$FAIL" -gt 0 ]; then
        warn "Some infrastructure components are not ready."
        warn "Start dev-infrastructure first: cd ../dev-infrastructure && ./scripts/init.sh"
        return 1
    fi

    log "All infrastructure health checks passed!"
    return 0
}

# ── K8s Resource Application ─────────────────────────────

TASK_VARS='${PIPELINE_NAMESPACE} ${KUBECTL_IMAGE} ${MAVEN_IMAGE} ${KANIKO_IMAGE} ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT} ${COMPONENT_NAME} ${VAULT_ADDRESS_PIPELINE} ${INFRA_DB_MOUNT} ${COMPONENT_MOUNT} ${POSTGRES_HOST} ${POSTGRES_PORT} ${MIGRATIONS_PATH}'
PIPELINE_VARS='${PIPELINE_NAMESPACE} ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH} ${IMAGE_NAME} ${IMAGE_TAG} ${REGISTRY_CLUSTER_HOST} ${REGISTRY_CLUSTER_PORT} ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT} ${KUBECTL_IMAGE} ${COMPONENT_NAME} ${VAULT_ADDRESS_PIPELINE} ${INFRA_DB_MOUNT} ${COMPONENT_MOUNT} ${POSTGRES_HOST} ${POSTGRES_PORT} ${MIGRATIONS_PATH}'
PIPELINE_RUN_VARS='${PIPELINE_NAMESPACE} ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH} ${IMAGE_NAME} ${IMAGE_TAG} ${REGISTRY_CLUSTER_HOST} ${REGISTRY_CLUSTER_PORT} ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT} ${PIPELINE_MODE} ${VAULT_ADDRESS_PIPELINE} ${COMPONENT_NAME} ${INFRA_DB_MOUNT} ${COMPONENT_MOUNT} ${POSTGRES_HOST} ${POSTGRES_PORT} ${MIGRATIONS_PATH}'
PVC_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAME}'
RBAC_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAME} ${RBAC_USER}'

apply_k8s_resources() {
    K8S_SETUP_DIR="$DEPLOYER_DIR/k8s-setup"
    TASKS_DIR="$DEPLOYER_DIR/tasks"
    PIPELINES_DIR="$DEPLOYER_DIR/pipelines"
    PVC_DIR="$DEPLOYER_DIR/pvc"

    log "Applying service RBAC..."
    if [ -f "$K8S_SETUP_DIR/rbac-role.yaml" ]; then
        envsubst "$RBAC_VARS" < "$K8S_SETUP_DIR/rbac-role.yaml" | kubectl apply -f - && log "  Applied: rbac-role.yaml" || warn "  Failed: rbac-role.yaml"
    fi
    if [ -f "$K8S_SETUP_DIR/rbac-rolebinding.yaml" ]; then
        envsubst "$RBAC_VARS" < "$K8S_SETUP_DIR/rbac-rolebinding.yaml" | kubectl apply -f - && log "  Applied: rbac-rolebinding.yaml (user: $RBAC_USER)" || warn "  Failed: rbac-rolebinding.yaml"
    fi

    log "Applying PVCs..."
    for pvc in "$PVC_DIR"/*.yaml; do
        if [ -f "$pvc" ]; then
            envsubst "$PVC_VARS" < "$pvc" | kubectl apply -f - && log "  Applied: $(basename "$pvc")" || warn "  Failed: $(basename "$pvc")"
        fi
    done

    log "Installing git-clone task from Tekton catalog..."
    kubectl apply -n "$PIPELINE_NAMESPACE" -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml 2>/dev/null || warn "Failed to install git-clone task (may already exist)"

    log "Applying service-specific tasks..."
    for task in "$TASKS_DIR"/*.yaml; do
        if [ -f "$task" ]; then
            envsubst "$TASK_VARS" < "$task" | kubectl apply -f - && log "  Applied: $(basename "$task")" || warn "  Failed: $(basename "$task")"
        fi
    done

    log "Applying pipeline..."
    for pipeline in "$PIPELINES_DIR"/*.yaml; do
        if [ -f "$pipeline" ]; then
            if [[ "$(basename "$pipeline")" == *pipeline-run* ]]; then
                log "  Skipping: $(basename "$pipeline")"
                continue
            fi
            envsubst "$PIPELINE_VARS" < "$pipeline" | kubectl apply -f - && log "  Applied: $(basename "$pipeline")" || warn "  Failed: $(basename "$pipeline")"
        fi
    done
}
