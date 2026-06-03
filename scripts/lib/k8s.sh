#!/bin/bash
# Kubernetes utilities: variable sets for envsubst, resource application.
# Sourced by register-resources.sh (and any script that applies k8s manifests).

# ── envsubst variable sets ────────────────────────────────
# Each set contains exactly the variables referenced in the corresponding manifest tree.
# Passing an explicit variable list to envsubst prevents accidental substitution of
# shell variables that happen to share a name with YAML content.

TASK_VARS='${PIPELINE_NAMESPACE} ${KUBECTL_IMAGE} ${MAVEN_IMAGE} ${KANIKO_IMAGE}
  ${DEPLOYMENT_PORT} ${DEPLOYMENT_NODEPORT}
  ${MIGRATIONS_PATH}
  ${MAVEN_SETTINGS_PATH}
  ${GRAVITEE_HOST} ${GRAVITEE_PORT} ${GRAVITEE_ORGANIZATION} ${GRAVITEE_ENVIRONMENT}
  ${GRAVITEE_CONTEXT_PATH} ${GRAVITEE_BACKEND_URL} ${INFRA_GRAVITEE_MOUNT} ${GRAVITEE_VERSION}'

PIPELINE_VARS='${PIPELINE_MODE} ${PIPELINE_NAMESPACE}
  ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH}
  ${IMAGE_NAME} ${IMAGE_TAG}
  ${MAVEN_SETTINGS_PATH}
  ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT} ${DEPLOYMENT_NODEPORT}
  ${KUBECTL_IMAGE}
  ${COMPONENT_NAME} ${VAULT_ADDRESS_PIPELINE}
  ${INFRA_DB_MOUNT} ${COMPONENT_MOUNT}
  ${POSTGRES_HOST} ${POSTGRES_PORT} ${DATABASE_HOST} ${DATABASE_PORT}
  ${PROPERTIES_REPO_URL} ${PROPERTIES_REPO_DEFAULT_BRANCH} ${ENVIRONMENT_NAME}
  ${GRAVITEE_HOST} ${GRAVITEE_PORT} ${GRAVITEE_ORGANIZATION} ${GRAVITEE_ENVIRONMENT}
  ${GRAVITEE_CONTEXT_PATH} ${GRAVITEE_BACKEND_URL} ${INFRA_GRAVITEE_MOUNT} ${GRAVITEE_VERSION}
  ${REGISTRY_CLUSTER_HOST} ${REGISTRY_CLUSTER_PORT}'

PIPELINE_RUN_VARS='${PIPELINE_MODE} ${PIPELINE_NAMESPACE} ${PIPELINE_SERVICE_ACCOUNT}
  ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH}
  ${IMAGE_NAME} ${IMAGE_TAG}
  ${MAVEN_SETTINGS_PATH}
  ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT} ${DEPLOYMENT_NODEPORT}
  ${KUBECTL_IMAGE}
  ${VAULT_ADDRESS_PIPELINE} ${COMPONENT_NAME}
  ${INFRA_DB_MOUNT} ${COMPONENT_MOUNT}
  ${POSTGRES_HOST} ${POSTGRES_PORT} ${DATABASE_HOST} ${DATABASE_PORT}
  ${PROPERTIES_REPO_URL} ${PROPERTIES_REPO_DEFAULT_BRANCH} ${ENVIRONMENT_NAME}
  ${GRAVITEE_HOST} ${GRAVITEE_PORT} ${GRAVITEE_ORGANIZATION} ${GRAVITEE_ENVIRONMENT}
  ${GRAVITEE_CONTEXT_PATH} ${GRAVITEE_BACKEND_URL} ${INFRA_GRAVITEE_MOUNT} ${GRAVITEE_VERSION}
  ${REGISTRY_CLUSTER_HOST} ${REGISTRY_CLUSTER_PORT}'

SECURITY_RUN_VARS='${PIPELINE_NAMESPACE} ${PIPELINE_SERVICE_ACCOUNT}
  ${GIT_REPO_URL} ${GIT_REPO_DEFAULT_BRANCH}
  ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME} ${DEPLOYMENT_PORT}
  ${SAST_FAIL_ON_CVSS} ${DAST_OPENAPI_PATH} ${DAST_FAIL_ON_RISK}'

RBAC_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAMESPACE} ${DEPLOYMENT_NAME}
  ${RBAC_USER} ${PIPELINE_SERVICE_ACCOUNT}'

STORAGE_VARS='${PIPELINE_NAMESPACE} ${DEPLOYMENT_NAME}'

HOST_SERVICE_VARS='${PIPELINE_NAMESPACE}
  ${VAULT_CONTAINER_IP} ${POSTGRES_CONTAINER_IP} ${GRAVITEE_CONTAINER_IP}
  ${VAULT_PORT} ${POSTGRES_PORT} ${GRAVITEE_PORT}'

# ── Host Endpoint Sync ────────────────────────────────────
# Docker containers (postgres, vault) may get new IPs on restart.
# This function patches the in-cluster Endpoints to match live container IPs.

sync_host_endpoints() {
    local _postgres_ip _vault_ip _gravitee_ip
    _postgres_ip=$(docker inspect postgres 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)
    _vault_ip=$(docker inspect vault 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)
    _gravitee_ip=$(docker inspect gravitee-mgmt-api 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin)[0]; nets=d['NetworkSettings']['Networks']; print(next((v['IPAddress'] for n,v in nets.items() if 'dev-infra' in n and v.get('IPAddress')), ''))" 2>/dev/null || true)

    for _ns in "$PIPELINE_NAMESPACE" "$DEPLOYMENT_NAMESPACE"; do
        if [ -n "$_postgres_ip" ]; then
            kubectl patch endpoints postgres-host -n "$_ns" \
                --patch "{\"subsets\":[{\"addresses\":[{\"ip\":\"${_postgres_ip}\"}],\"ports\":[{\"port\":${POSTGRES_PORT:-5432}}]}]}" \
                &>/dev/null \
                && log "  Synced postgres-host Endpoint → ${_postgres_ip} (${_ns})" \
                || warn "  Failed to sync postgres-host Endpoint in ${_ns}"
        fi
        if [ -n "$_vault_ip" ]; then
            kubectl patch endpoints vault-host -n "$_ns" \
                --patch "{\"subsets\":[{\"addresses\":[{\"ip\":\"${_vault_ip}\"}],\"ports\":[{\"port\":${VAULT_PORT:-8201}}]}]}" \
                &>/dev/null \
                && log "  Synced vault-host Endpoint → ${_vault_ip} (${_ns})" \
                || warn "  Failed to sync vault-host Endpoint in ${_ns}"
        fi
        if [ -n "$_gravitee_ip" ]; then
            kubectl patch endpoints gravitee-host -n "$_ns" \
                --patch "{\"subsets\":[{\"addresses\":[{\"ip\":\"${_gravitee_ip}\"}],\"ports\":[{\"port\":${GRAVITEE_PORT:-8083}}]}]}" \
                &>/dev/null \
                && log "  Synced gravitee-host Endpoint → ${_gravitee_ip} (${_ns})" \
                || warn "  Failed to sync gravitee-host Endpoint in ${_ns}"
        fi
    done
}

# ── Resource Application ──────────────────────────────────

apply_k8s_resources() {
    K8S_SETUP_DIR="$DEPLOYER_DIR/components/kubernetes"
    TASKS_DIR="$DEPLOYER_DIR/components/tekton/tasks"
    PIPELINES_DIR="$DEPLOYER_DIR/components/tekton/pipelines"
    TEMPLATES_DIR="$DEPLOYER_DIR/components/kubernetes/app"

    # Host gateway services (Vault + Postgres reachable from pods)
    log "Applying host gateway services (vault-host, postgres-host)..."
    if [ -f "$K8S_SETUP_DIR/host-services.yaml" ]; then
        for _ns in "$PIPELINE_NAMESPACE" "$DEPLOYMENT_NAMESPACE"; do
            envsubst "$HOST_SERVICE_VARS" < "$K8S_SETUP_DIR/host-services.yaml" \
                | sed "s/namespace: ${PIPELINE_NAMESPACE}/namespace: ${_ns}/g" \
                | kubectl apply -f - \
                && log "  Applied: host-services.yaml → ${_ns}" \
                || warn "  Failed: host-services.yaml → ${_ns}"
        done
    fi

    # Gravitee gateway service — only when container IP is known
    if [ -n "${GRAVITEE_CONTAINER_IP:-}" ] && [ -f "$K8S_SETUP_DIR/host-services-gravitee.yaml" ]; then
        log "Applying host gateway service (gravitee-host)..."
        for _ns in "$PIPELINE_NAMESPACE" "$DEPLOYMENT_NAMESPACE"; do
            envsubst "$HOST_SERVICE_VARS" < "$K8S_SETUP_DIR/host-services-gravitee.yaml" \
                | sed "s/namespace: ${PIPELINE_NAMESPACE}/namespace: ${_ns}/g" \
                | kubectl apply -f - \
                && log "  Applied: host-services-gravitee.yaml → ${_ns}" \
                || warn "  Failed: host-services-gravitee.yaml → ${_ns}"
        done
    else
        log "Skipping gravitee-host (GRAVITEE_CONTAINER_IP not set — gravitee not running)"
    fi

    # Sync Endpoint IPs from live containers (handles container recreations)
    sync_host_endpoints

    # Storage: PVCs
    log "Applying PVCs..."
    for _pvc in "$K8S_SETUP_DIR/storage"/*.yaml; do
        [ -f "$_pvc" ] || continue
        envsubst "$STORAGE_VARS" < "$_pvc" | kubectl apply -f - \
            && log "  Applied: $(basename "$_pvc")" \
            || warn "  Failed: $(basename "$_pvc")"
    done

    # RBAC: service account + roles + bindings (all namespaces)
    log "Applying RBAC (service account, roles, bindings)..."
    for _rbac in "$K8S_SETUP_DIR/rbac"/*.yaml; do
        [ -f "$_rbac" ] || continue
        envsubst "$RBAC_VARS" < "$_rbac" | kubectl apply -f - \
            && log "  Applied: $(basename "$_rbac")" \
            || warn "  Failed: $(basename "$_rbac")"
    done

    # Deployment template → ConfigMap (used by deploy task)
    log "Creating ConfigMaps from templates..."
    for _tpl in "$TEMPLATES_DIR"/*.yaml; do
        [ -f "$_tpl" ] || continue
        TEMPLATE_NAME="$(basename "$_tpl" .yaml)-template"
        kubectl create configmap "$TEMPLATE_NAME" \
            -n "$PIPELINE_NAMESPACE" \
            --from-file="$_tpl" \
            --dry-run=client -o yaml | kubectl apply -f - \
            && log "  Applied: $(basename "$_tpl") → ConfigMap/${TEMPLATE_NAME}" \
            || warn "  Failed: $(basename "$_tpl")"
    done

    # Tekton catalog: git-clone task
    log "Installing git-clone task from Tekton catalog..."
    kubectl apply -n "$PIPELINE_NAMESPACE" \
        -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml \
        2>/dev/null || warn "Failed to install git-clone task (may already exist)"

    # Tasks — flat directory, apply in sorted order
    log "Applying Tekton tasks..."
    for _task in "$TASKS_DIR"/*.yaml; do
        [ -f "$_task" ] || continue
        envsubst "$TASK_VARS" < "$_task" | kubectl apply -f - \
            && log "  Applied: $(basename "$_task")" \
            || warn "  Failed: $(basename "$_task")"
    done

    # Pipelines
    log "Applying Tekton pipelines..."
    _pfile="$PIPELINES_DIR/pipeline.yaml"
    if [ -f "$_pfile" ]; then
        envsubst "$PIPELINE_VARS" < "$_pfile" | kubectl apply -f - \
            && log "  Applied: pipeline.yaml" \
            || warn "  Failed: pipeline.yaml"
    fi

    _sfile="$PIPELINES_DIR/security-pipeline.yaml"
    if [ -f "$_sfile" ]; then
        envsubst "$PIPELINE_VARS" < "$_sfile" | kubectl apply -f - \
            && log "  Applied: security-pipeline.yaml" \
            || warn "  Failed: security-pipeline.yaml"
    fi
}
