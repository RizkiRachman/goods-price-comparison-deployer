#!/bin/bash
# Core utilities: logging, progress spinner, timer, environment loading, prerequisite checks.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$_LIB_DIR")"
DEPLOYER_DIR="$(dirname "$SCRIPTS_DIR")"
TERRAFORM_DIR="$DEPLOYER_DIR/components/terraform"

# ── Logging ───────────────────────────────────────────────

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

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
    local _env_file=""
    if [ -f "$DEPLOYER_DIR/.env" ]; then
        _env_file="$DEPLOYER_DIR/.env"
    elif [ -f "$(pwd)/.env" ]; then
        _env_file="$(pwd)/.env"
    fi

    if [ -n "$_env_file" ]; then
        set -a && source "$_env_file" && set +a
    else
        warn ".env file not found. Some defaults will be used."
    fi

    # Load environment-specific overrides
    local _mode="${PIPELINE_MODE:-local}"
    local _mode_file=""
    if [ -f "$DEPLOYER_DIR/.env.${_mode}" ]; then
        _mode_file="$DEPLOYER_DIR/.env.${_mode}"
    elif [ -f "$(pwd)/.env.${_mode}" ]; then
        _mode_file="$(pwd)/.env.${_mode}"
    fi
    if [ -n "$_mode_file" ]; then
        set -a && source "$_mode_file" && set +a
    fi
}

set_defaults() {
    VAULT_ADDRESS_TERRAFORM="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}"
    PIPELINE_MODE="${PIPELINE_MODE:-local}"
    DEPLOYMENT_NAMESPACE="${DEPLOYMENT_NAMESPACE:-dev-infrastructure}"
    DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-goods-price-comparison-service}"
    DEPLOYMENT_PORT="${DEPLOYMENT_PORT:-8080}"
    DEPLOYMENT_NODEPORT="${DEPLOYMENT_NODEPORT:-30080}"
    KUBECTL_IMAGE="${KUBECTL_IMAGE:-bitnami/kubectl:latest}"
    MAVEN_IMAGE="${MAVEN_IMAGE:-maven:3.9-eclipse-temurin-17}"
    KANIKO_IMAGE="${KANIKO_IMAGE:-gcr.io/kaniko-project/executor:latest}"
    RBAC_USER="${RBAC_USER:-dev-infra-admin}"
    PIPELINE_SERVICE_ACCOUNT="${PIPELINE_SERVICE_ACCOUNT:-dev-infra}"
    IMAGE_NAME="${IMAGE_NAME:-goods-price-comparison-service}"
    IMAGE_TAG="${IMAGE_TAG:-latest}"
    REGISTRY_CLUSTER_HOST="${REGISTRY_CLUSTER_HOST:-k3d-dev-infra-registry}"
    REGISTRY_CLUSTER_PORT="${REGISTRY_CLUSTER_PORT:-5000}"
    MAVEN_SETTINGS_PATH="${MAVEN_SETTINGS_PATH:-/home/deploy/.m2/settings.xml}"
    GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/RizkiRachman/goods-price-comparison-service.git}"
    GIT_REPO_DEFAULT_BRANCH="${GIT_REPO_DEFAULT_BRANCH:-main}"

    # Vault and Postgres container IPs on the dev-infra Docker network
    if [ -z "${VAULT_CONTAINER_IP:-}" ]; then
        VAULT_CONTAINER_IP=$(docker inspect vault 2>/dev/null | \
            python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)
        VAULT_CONTAINER_IP="${VAULT_CONTAINER_IP:-172.21.0.5}"
    fi
    if [ -z "${POSTGRES_CONTAINER_IP:-}" ]; then
        POSTGRES_CONTAINER_IP=$(docker inspect postgres 2>/dev/null | \
            python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)
        POSTGRES_CONTAINER_IP="${POSTGRES_CONTAINER_IP:-172.21.0.4}"
    fi
    export VAULT_CONTAINER_IP POSTGRES_CONTAINER_IP
    VAULT_PORT="${VAULT_PORT:-8201}"
    export VAULT_PORT POSTGRES_PORT

    VAULT_ADDRESS_PIPELINE="${VAULT_ADDRESS_PIPELINE:-http://vault-host:${VAULT_PORT}}"
    INFRA_DB_MOUNT="${INFRA_DB_MOUNT:-local/infrastructure}"
    COMPONENT_MOUNT="${COMPONENT_MOUNT:-local/component}"
    POSTGRES_HOST="${POSTGRES_HOST:-postgres-host}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"
    DATABASE_HOST="${DATABASE_HOST:-${POSTGRES_HOST}}"
    DATABASE_PORT="${DATABASE_PORT:-${POSTGRES_PORT}}"
    MIGRATIONS_PATH="${MIGRATIONS_PATH:-db/migration}"
    COMPONENT_NAME="${COMPONENT_NAME:-${DEPLOYMENT_NAME}}"
    PROPERTIES_REPO_URL="${PROPERTIES_REPO_URL:-https://github.com/${RBAC_USER}/goods-price-comparison-properties.git}"
    PROPERTIES_REPO_DEFAULT_BRANCH="${PROPERTIES_REPO_DEFAULT_BRANCH:-main}"
    ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"

    GRAVITEE_HOST="${GRAVITEE_HOST:-gravitee-host}"
    GRAVITEE_PORT="${GRAVITEE_PORT:-8083}"
    GRAVITEE_GATEWAY_PORT="${GRAVITEE_GATEWAY_PORT:-8082}"
    GRAVITEE_LOCAL_HOST="${GRAVITEE_LOCAL_HOST:-dev.good-prices}"
    GRAVITEE_ORGANIZATION="${GRAVITEE_ORGANIZATION:-DEFAULT}"
    GRAVITEE_ENVIRONMENT="${GRAVITEE_ENVIRONMENT:-DEFAULT}"
    GRAVITEE_CONTEXT_PATH="${GRAVITEE_CONTEXT_PATH:-/${DEPLOYMENT_NAME}}"
    if [ -z "${GRAVITEE_BACKEND_URL:-}" ]; then
        _K3D_NODE_IP=$(docker inspect k3d-dev-infra-server-0 2>/dev/null | \
            python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)
        _K3D_NODEPORT=$(kubectl get svc "${DEPLOYMENT_NAME}" -n "${DEPLOYMENT_NAMESPACE}" \
            -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
        if [ -n "${_K3D_NODE_IP}" ] && [ -n "${_K3D_NODEPORT}" ]; then
            GRAVITEE_BACKEND_URL="http://${_K3D_NODE_IP}:${_K3D_NODEPORT}"
        else
            GRAVITEE_BACKEND_URL="http://host.k3d.internal:${DEPLOYMENT_NODEPORT}"
        fi
    fi
    INFRA_GRAVITEE_MOUNT="${INFRA_GRAVITEE_MOUNT:-local/infrastructure}"
    GRAVITEE_VERSION="${GRAVITEE_VERSION:-}"

    SAST_FAIL_ON_CVSS="${SAST_FAIL_ON_CVSS:-7}"
    DAST_OPENAPI_PATH="${DAST_OPENAPI_PATH:-/v3/api-docs}"
    DAST_FAIL_ON_RISK="${DAST_FAIL_ON_RISK:-2}"

    SMOKE_TUNNEL_PORT="${SMOKE_TUNNEL_PORT:-9080}"

    if [ -z "${GRAVITEE_CONTAINER_IP:-}" ]; then
        GRAVITEE_CONTAINER_IP=$(docker inspect gravitee-mgmt-api 2>/dev/null | \
            python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)
        GRAVITEE_CONTAINER_IP="${GRAVITEE_CONTAINER_IP:-}"
    fi
    export GRAVITEE_CONTAINER_IP
}

# ── Local Domain ─────────────────────────────────────────

check_local_domain() {
    local domain="${1:-${GRAVITEE_LOCAL_HOST:-dev.good-prices}}"
    if grep -qE "^\s*127\.0\.0\.1\s+${domain}" /etc/hosts 2>/dev/null; then
        return 0
    fi
    echo ""
    warn "  Local domain '${domain}' not found in /etc/hosts."
    echo "  Add it with:"
    echo ""
    echo "    echo '127.0.0.1  ${domain}' | sudo tee -a /etc/hosts"
    echo ""
    return 1
}

# ── Prerequisite Checks ───────────────────────────────────

check_prerequisites() {
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster. Start dev-infrastructure first."
    fi
    if ! kubectl get namespace "${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}" &>/dev/null; then
        error "Namespace '${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}' not found. Run dev-infrastructure setup first."
    fi
}

check_terraform() {
    if ! command -v terraform &>/dev/null; then
        error "terraform not found. Install Terraform first: https://developer.hashicorp.com/terraform/install"
    fi
}

check_tekton_pipeline() {
    local _name="${DEPLOYMENT_NAME:-goods-price-service}-pipeline"
    if ! kubectl get pipeline "$_name" -n "${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}" &>/dev/null; then
        error "Pipeline '${_name}' not found. Run ./installation/init.sh first."
    fi
}

# ── Infrastructure Health Check ───────────────────────────

health_check_infra() {
    local PASS=0 FAIL=0

    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│         Infrastructure Health Check          │"
    echo "└─────────────────────────────────────────────┘"

    if kubectl cluster-info &>/dev/null; then
        log "  Kubernetes cluster: reachable"; PASS=$((PASS+1))
    else
        warn "  Kubernetes cluster: unreachable"; FAIL=$((FAIL+1))
    fi

    if kubectl get namespace "${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}" &>/dev/null; then
        log "  Namespace '${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}': exists"; PASS=$((PASS+1))
    else
        warn "  Namespace '${PIPELINE_NAMESPACE:-dev-infrastructure-pipelines}': not found"; FAIL=$((FAIL+1))
    fi

    if kubectl get crd tasks.tekton.dev &>/dev/null; then
        log "  Tekton Pipelines: installed"; PASS=$((PASS+1))
    else
        warn "  Tekton Pipelines: not installed"; FAIL=$((FAIL+1))
    fi

    local _vault_addr="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    local _vault_http_code
    _vault_http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${_vault_addr}/v1/sys/health" 2>/dev/null)
    if [[ "$_vault_http_code" =~ ^(200|429|472|473)$ ]]; then
        log "  Vault (${_vault_addr}): reachable (HTTP ${_vault_http_code})"; PASS=$((PASS+1))
    else
        warn "  Vault (${_vault_addr}): unreachable (HTTP ${_vault_http_code:-000})"; FAIL=$((FAIL+1))
    fi

    if [ "${PIPELINE_MODE:-local}" = "local" ]; then
        if curl -sf "http://localhost:${REGISTRY_PORT:-5002}/v2/" &>/dev/null; then
            log "  Registry (localhost:${REGISTRY_PORT:-5002}): reachable"; PASS=$((PASS+1))
        else
            warn "  Registry (localhost:${REGISTRY_PORT:-5002}): unreachable"; FAIL=$((FAIL+1))
        fi
    else
        log "  Registry: skipped (production mode — VPS deploy)"; PASS=$((PASS+1))
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
