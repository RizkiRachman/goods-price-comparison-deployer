#!/bin/bash
# Init: set up infrastructure + health check.
# Registers service-specific resources (Terraform secrets, RBAC, PVCs, tasks, pipelines)
# and verifies all infrastructure connectivity. Does NOT deploy the service.
#
# Usage: ./scripts/init.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/vault.sh"
source "$SCRIPT_DIR/lib/k8s.sh"
source "$SCRIPT_DIR/stages/init-infra.sh"

load_env
set_defaults
check_terraform

export TF_VAR_vault_address="${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
export TF_VAR_vault_token="${VAULT_TOKEN:-}"

if [ -z "${VAULT_TOKEN}" ]; then
    error "VAULT_TOKEN is not set. Add VAULT_TOKEN=<your-vault-token> to your .env file."
fi

echo ""
echo "=========================================="
echo "  INIT — Setup Infrastructure + Health Check"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Vault:   ${VAULT_ADDRESS_TERRAFORM:-http://localhost:8201}"
echo "  K8s:     ${PIPELINE_NAMESPACE}"
echo ""

timer_start

stage "Health Check — verifying infrastructure connectivity"
if ! health_check_infra; then
    error "Infrastructure health check failed. Start dev-infrastructure first."
fi

stage "Vault — checking connectivity"
check_vault

stage "Vault — ensuring KV mounts exist"
ensure_vault_mounts

stage "Vault — verifying required secrets exist"
check_vault_secrets

stage "Terraform — Vault → K8s secrets"
cd "$TERRAFORM_DIR"

if [ ! -f "terraform.tfvars" ]; then
    warn "terraform.tfvars not found."
    if [ -f "terraform.tfvars.example" ]; then
        log "Copying terraform.tfvars.example → terraform.tfvars"
        cp terraform.tfvars.example terraform.tfvars
        warn "Edit terraform/terraform.tfvars with your Vault token before continuing."
        error "Set vault_token in terraform/terraform.tfvars, then re-run init."
    else
        error "No terraform.tfvars.example found. Create terraform.tfvars manually."
    fi
fi

log "Running terraform init..."
terraform init -upgrade

log "Applying Terraform (creating K8s secrets from Vault)..."
terraform apply -auto-approve
log "Terraform apply complete — K8s secrets created from Vault."

stage "K8s Resources — RBAC, PVCs, tasks, pipelines"
apply_k8s_resources

stage "Health Check — verifying service resources"

if terraform state list 2>/dev/null | grep -q "kubernetes_secret"; then
    log "  Terraform secrets: registered in state"
else
    warn "  Terraform secrets: not found in state"
fi

if kubectl get sa "${PIPELINE_SERVICE_ACCOUNT}" -n "$PIPELINE_NAMESPACE" &>/dev/null; then
    log "  ServiceAccount '${PIPELINE_SERVICE_ACCOUNT}': exists"
else
    warn "  ServiceAccount '${PIPELINE_SERVICE_ACCOUNT}': not found"
fi

if kubectl get pipeline "${DEPLOYMENT_NAME}-pipeline" -n "$PIPELINE_NAMESPACE" &>/dev/null; then
    log "  Pipeline '${DEPLOYMENT_NAME}-pipeline': registered"
else
    warn "  Pipeline '${DEPLOYMENT_NAME}-pipeline': not found"
fi

if kubectl get pvc "${DEPLOYMENT_NAME}-pvc" -n "$PIPELINE_NAMESPACE" &>/dev/null; then
    log "  PVC '${DEPLOYMENT_NAME}-pvc': bound"
else
    warn "  PVC '${DEPLOYMENT_NAME}-pvc': not found"
fi

echo ""
echo "=========================================="
echo "  INIT COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Infrastructure ready:"
echo "    - K8s secrets from Vault"
echo "    - RBAC (pipeline + deployment namespaces)"
echo "    - PVCs (workspace + maven cache)"
echo "    - Tekton tasks + pipeline"
echo ""
echo "  Next steps:"
echo "    ./scripts/apply.sh    # Full build + deploy"
