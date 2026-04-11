#!/bin/bash
# Init: Setup infrastructure + health check
# Registers service-specific resources (Terraform secrets, RBAC, PVCs, tasks, pipeline)
# and verifies all infrastructure connectivity. Does NOT deploy the service.
#
# Usage: ./scripts/init.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib + stages
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/stages/init-infra.sh"

load_env
set_defaults
check_terraform

# Export Vault config for Terraform (overrides terraform.tfvars values)
export TF_VAR_vault_address="${VAULT_ADDRESS:-http://localhost:8201}"
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
echo "  Vault:   ${VAULT_ADDRESS:-http://localhost:8201}"
echo "  K8s:     ${PIPELINE_NAMESPACE}"
echo ""

timer_start

# ── Health Check: verify dev-infrastructure is running ──

stage "Health Check — verifying infrastructure connectivity"
if ! health_check_infra; then
    error "Infrastructure health check failed. Start dev-infrastructure first."
fi

# ── Vault Reachability ──

stage "Vault — checking connectivity"
check_vault

# ── Terraform: Vault → K8s secrets ──

stage "Terraform — Vault → K8s secrets"
cd "$TERRAFORM_DIR"

# Ensure tfvars exists
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

# Terraform init if needed
if [ ! -d ".terraform" ]; then
    log "Running terraform init..."
    terraform init
else
    log "Terraform already initialized."
fi

# Apply Terraform (create K8s secrets from Vault)
log "Applying Terraform (creating K8s secrets from Vault)..."
terraform apply -auto-approve
log "Terraform apply complete — K8s secrets created from Vault."

# ── K8s Resources: RBAC, PVCs, tasks, pipeline ──

stage "K8s Resources — RBAC, PVCs, tasks, pipeline"
apply_k8s_resources

# ── Final Health Check: verify service resources ──

stage "Health Check — verifying service resources"

# Verify Terraform state (secrets managed by Terraform, not kubectl)
if terraform state list 2>/dev/null | grep -q "kubernetes_secret"; then
    log "  ✅ Terraform secrets: registered in state"
else
    warn "  ❌ Terraform secrets: not found in state"
fi

if kubectl get pipeline goods-price-pipeline -n "$PIPELINE_NAMESPACE" &>/dev/null; then
    log "  ✅ Pipeline 'goods-price-pipeline': registered"
else
    warn "  ❌ Pipeline 'goods-price-pipeline': not found"
fi

if kubectl get pvc "${DEPLOYMENT_NAME}-pvc" -n "$PIPELINE_NAMESPACE" &>/dev/null; then
    log "  ✅ PVC '${DEPLOYMENT_NAME}-pvc': bound"
else
    warn "  ❌ PVC '${DEPLOYMENT_NAME}-pvc': not found"
fi

echo ""
echo "=========================================="
echo "  ✅ INIT COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Infrastructure ready:"
echo "    - K8s secrets from Vault"
echo "    - RBAC (Role + RoleBinding)"
echo "    - PVCs (workspace + maven cache)"
echo "    - Tekton tasks + pipeline"
echo ""
echo "  Next steps:"
echo "    ./scripts/apply.sh    # Build + deploy service"
echo "    ./scripts/plan.sh     # Dry-run + diff preview"
