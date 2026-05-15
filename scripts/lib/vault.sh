#!/bin/bash
# Vault utilities: connectivity checks, mount management, secret validation.
# Sourced by scripts that interact with Vault (register-resources.sh, etc.).

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

ensure_vault_mounts() {
    local _vault_addr="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    local _token="${VAULT_TOKEN:-}"

    for _mount in "${INFRA_DB_MOUNT:-local/infrastructure}" "${COMPONENT_MOUNT:-local/component}"; do
        local _http_code
        _http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "X-Vault-Token: ${_token}" \
            "${_vault_addr}/v1/sys/mounts/${_mount}" 2>/dev/null)

        if [[ "$_http_code" == "200" ]]; then
            log "  Vault mount '${_mount}': exists"
        else
            log "  Vault mount '${_mount}': not found, enabling KV v2..."
            local _response
            _response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                -H "X-Vault-Token: ${_token}" \
                -H "Content-Type: application/json" \
                -d '{"type":"kv","options":{"version":"2"}}' \
                "${_vault_addr}/v1/sys/mounts/${_mount}" 2>/dev/null)
            if [[ "$_response" == "204" ]]; then
                log "  Vault mount '${_mount}': enabled"
            else
                error "Failed to enable Vault mount '${_mount}' (HTTP ${_response}). Check token permissions."
            fi
        fi
    done
}

check_vault_secrets() {
    local _vault_addr="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
    local _token="${VAULT_TOKEN:-}"
    local _mount="${INFRA_DB_MOUNT:-local/infrastructure}"
    local _failed=0

    log "Checking required Vault secrets..."

    for _secret in "${GITHUB_SECRET_NAME:-github}" "${DATABASE_SECRET_NAME:-database}" "vps"; do
        local _http_code
        _http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "X-Vault-Token: ${_token}" \
            "${_vault_addr}/v1/${_mount}/data/${_secret}" 2>/dev/null)
        if [[ "$_http_code" == "200" ]]; then
            log "  Vault secret '${_mount}/data/${_secret}': found"
        else
            warn "  Vault secret '${_mount}/data/${_secret}': not found (HTTP ${_http_code:-000})"
            _failed=$((_failed + 1))
        fi
    done

    if [ "$_failed" -gt 0 ]; then
        error "Required Vault secrets are missing. Run dev-infrastructure setup first: cd ../dev-infrastructure && ./scripts/init.sh"
    fi
}
