#!/bin/bash
# Destroy: Delete all service resources and deployment
# Does NOT delete shared infrastructure (namespace, SA, ClusterRole, registry secret)
#
# Usage: ./scripts/destroy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib
source "$SCRIPT_DIR/lib/common.sh"

load_env
set_defaults
check_prerequisites
check_terraform

PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-goods-price-service}"

echo ""
echo "=========================================="
echo "  DESTROY — Remove All Service Resources"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Namespace: ${PIPELINE_NAMESPACE}"
echo ""

warn "This will delete ALL service-specific resources in namespace: ${PIPELINE_NAMESPACE}"
warn "Shared infrastructure (SA, ClusterRole, registry secret) will NOT be deleted."
echo ""
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

timer_start

# Stage 1: Delete deployment
stage "Delete Deployment"
if kubectl get deployment "$DEPLOYMENT_NAME" -n "$DEPLOYMENT_NAMESPACE" &>/dev/null; then
    kubectl delete deployment "$DEPLOYMENT_NAME" -n "$DEPLOYMENT_NAMESPACE"
    log "Deployment deleted: ${DEPLOYMENT_NAME}"
else
    log "Deployment not found, skipping."
fi

# Stage 2: Delete K8s resources
stage "Delete K8s Resources"

log "Deleting PipelineRuns..."
kubectl delete pipelineruns -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipeline=goods-price-pipeline 2>/dev/null || true

log "Deleting TaskRuns..."
kubectl delete taskruns -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipeline=goods-price-pipeline 2>/dev/null || true

log "Deleting Pipeline..."
kubectl delete pipeline goods-price-pipeline -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting Tasks..."
kubectl delete task cleanup maven-build maven-test docker-build deploy -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting PVCs..."
kubectl delete pvc "${DEPLOYMENT_NAME}-pvc" maven-cache-pvc -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting service RBAC..."
kubectl delete rolebinding "${DEPLOYMENT_NAME}-binding" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true
kubectl delete role "${DEPLOYMENT_NAME}-role" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

# Stage 3: Destroy Terraform-managed secrets
stage "Destroy Terraform Secrets"
cd "$TERRAFORM_DIR"

if [ -f "terraform.tfvars" ]; then
    terraform destroy -auto-approve
    log "Terraform secrets destroyed."
else
    error "terraform.tfvars not found. Cannot destroy secrets without Terraform config. Run ./scripts/init.sh first."
fi

echo ""
echo "=========================================="
echo "  ✅ DESTROY COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  All service resources removed."
echo "  Shared infrastructure still running in namespace: ${PIPELINE_NAMESPACE}"
