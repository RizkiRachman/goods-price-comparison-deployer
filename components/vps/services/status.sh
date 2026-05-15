#!/bin/bash
# Status: check if the service pods are running and print port-forward instructions.
#
# Usage: ./scripts/status.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../../scripts/lib/common.sh"

load_env
set_defaults

if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster."
fi

stage "Checking deployment: ${DEPLOYMENT_NAMESPACE}/${DEPLOYMENT_NAME}"

if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${DEPLOYMENT_NAMESPACE}" &>/dev/null; then
    log "Deployment '${DEPLOYMENT_NAME}' not found in namespace '${DEPLOYMENT_NAMESPACE}'."
    log "Run ./scripts/apply.sh first to deploy the service."
    exit 0
fi

log "Deployment '${DEPLOYMENT_NAME}' exists."

PODS=$(kubectl get pods -n "${DEPLOYMENT_NAMESPACE}" -l app="${DEPLOYMENT_NAME}" -o name 2>/dev/null || true)

if [ -z "$PODS" ]; then
    log "No pods found for deployment '${DEPLOYMENT_NAME}'."
    exit 0
fi

RUNNING=0
for pod in $PODS; do
    POD_NAME=$(echo "$pod" | cut -d'/' -f2)
    STATUS=$(kubectl get pod "$POD_NAME" -n "${DEPLOYMENT_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Running" ]; then
        RUNNING=$((RUNNING+1))
        log "  Pod '${POD_NAME}': Running"
    else
        log "  Pod '${POD_NAME}': ${STATUS}"
    fi
done

echo ""
if [ "$RUNNING" -eq 0 ]; then
    warn "No pods are in Running state yet."
    exit 0
fi

log "${RUNNING} pod(s) running."

echo ""
echo "┌─────────────────────────────────────────────┐"
echo "│              Access Information              │"
echo "└─────────────────────────────────────────────┘"
echo ""

# ── Local domain check (once, shared by both sections) ────
check_local_domain "${GRAVITEE_LOCAL_HOST}" || true

# ── Build URL bases ───────────────────────────────────────
if [ "${GRAVITEE_GATEWAY_PORT}" = "80" ] || [ "${GRAVITEE_GATEWAY_PORT}" = "443" ]; then
    GW_BASE="http://${GRAVITEE_LOCAL_HOST}${GRAVITEE_CONTEXT_PATH}"
else
    GW_BASE="http://${GRAVITEE_LOCAL_HOST}:${GRAVITEE_GATEWAY_PORT}${GRAVITEE_CONTEXT_PATH}"
fi
DIRECT_BASE="http://${GRAVITEE_LOCAL_HOST}:${DEPLOYMENT_NODEPORT}"

# ── Gravitee Gateway ──────────────────────────────────────
MGMT_BASE="http://localhost:${GRAVITEE_PORT}/management"
APIS_PATH="v2/environments/${GRAVITEE_ENVIRONMENT}/apis"
GV_API_STATE=""
GV_REACHABLE=false

GV_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    "${MGMT_BASE}/openapi.json" 2>/dev/null || true)
if [[ "${GV_HTTP}" =~ ^(200|401|403)$ ]]; then
    GV_REACHABLE=true
fi

if [ "${GV_REACHABLE}" = true ]; then
    GV_USERNAME="${GV_ADMIN_USERNAME:-admin}"
    GV_PASSWORD="${GV_ADMIN_PASSWORD:-admin}"
    AUTH_RESP=$(curl -sf -X POST \
        "${MGMT_BASE}/organizations/${GRAVITEE_ORGANIZATION}/user/login" \
        -H "Authorization: Basic $(echo -n "${GV_USERNAME}:${GV_PASSWORD}" | base64)" \
        2>/dev/null || true)
    GV_TOKEN=$(echo "${AUTH_RESP}" | jq -r '.token // .payload // empty' 2>/dev/null || true)
    if [ -n "${GV_TOKEN}" ] && [ "${GV_TOKEN}" != "null" ]; then
        GV_AUTH="Bearer ${GV_TOKEN}"
    else
        GV_AUTH="Basic $(echo -n "${GV_USERNAME}:${GV_PASSWORD}" | base64)"
    fi

    GV_API_LIST=$(curl -sf -H "Authorization: ${GV_AUTH}" \
        "${MGMT_BASE}/${APIS_PATH}" 2>/dev/null || true)
    GV_API_ID=$(echo "${GV_API_LIST}" | \
        jq -r --arg n "${DEPLOYMENT_NAME}" \
        'if .data then .data[]? else .[]? end | select(.name==$n) | .id' 2>/dev/null || true)

    if [ -n "${GV_API_ID}" ]; then
        GV_API_STATE=$(curl -sf -H "Authorization: ${GV_AUTH}" \
            "${MGMT_BASE}/${APIS_PATH}/${GV_API_ID}" 2>/dev/null | \
            jq -r '.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    fi
fi

echo "  Via Gravitee Gateway"
if [ "${GV_REACHABLE}" = false ]; then
    warn "  Gravitee unreachable (localhost:${GRAVITEE_PORT})"
elif [ -z "${GV_API_ID}" ]; then
    warn "  API '${DEPLOYMENT_NAME}' not registered — run ./scripts/apply.sh"
else
    if [ "${GV_API_STATE}" = "STARTED" ]; then
        log "  API state: ${GV_API_STATE}"
    else
        warn "  API state: ${GV_API_STATE}"
    fi
    echo "    ${GW_BASE}"
    echo "    curl ${GW_BASE}/actuator/health"
fi

echo ""
echo "  ─────────────────────────────────────────────"
echo "  Direct (NodePort — bypasses Gravitee)"
echo "    ${DIRECT_BASE}"
echo "    curl ${DIRECT_BASE}/actuator/health"
echo ""
echo "  ─────────────────────────────────────────────"
echo "  Port-Forward"
echo "    kubectl port-forward -n ${DEPLOYMENT_NAMESPACE} \\"
echo "      deployment/${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT}:${DEPLOYMENT_PORT}"
echo "    curl http://localhost:${DEPLOYMENT_PORT}/actuator/health"
echo ""
