#!/bin/bash
# Destroy: delete all service resources and deployment.
# Does NOT delete shared infrastructure (namespace, SA, ClusterRole, registry secret).
#
# Usage: ./scripts/destroy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

load_env
set_defaults
check_prerequisites
check_terraform

echo ""
echo "=========================================="
echo "  DESTROY — Remove All Service Resources"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Pipeline namespace: ${PIPELINE_NAMESPACE}"
echo "  Deployment namespace: ${DEPLOYMENT_NAMESPACE}"
echo ""

warn "This will delete ALL service-specific resources in the above namespaces."
warn "Shared infrastructure (SA, ClusterRole, registry secret) will NOT be deleted."
echo ""
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

timer_start

stage "Delete Deployment"
if kubectl get deployment "$DEPLOYMENT_NAME" -n "$DEPLOYMENT_NAMESPACE" &>/dev/null; then
    kubectl delete deployment "$DEPLOYMENT_NAME" -n "$DEPLOYMENT_NAMESPACE"
    log "Deployment deleted: ${DEPLOYMENT_NAME}"
else
    log "Deployment not found, skipping."
fi

stage "Delete K8s Resources"

log "Deleting PipelineRuns..."
kubectl delete pipelineruns -n "$PIPELINE_NAMESPACE" \
    -l tekton.dev/pipeline=${DEPLOYMENT_NAME}-pipeline 2>/dev/null || true

log "Deleting TaskRuns..."
kubectl delete taskruns -n "$PIPELINE_NAMESPACE" \
    -l tekton.dev/pipeline=${DEPLOYMENT_NAME}-pipeline 2>/dev/null || true

log "Deleting Pipeline..."
kubectl delete pipeline "${DEPLOYMENT_NAME}-pipeline" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting Tasks..."
kubectl delete task cleanup maven-build maven-test docker-build \
    db-provision db-migrate config-apply deploy gravitee-register \
    -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting ConfigMaps..."
kubectl delete configmap "${DEPLOYMENT_NAME}-config" -n "$DEPLOYMENT_NAMESPACE" 2>/dev/null || true
kubectl delete configmap deployment-template service-template -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting Service..."
kubectl delete service "${DEPLOYMENT_NAME}" -n "$DEPLOYMENT_NAMESPACE" 2>/dev/null || true

log "Deleting PVCs..."
kubectl delete pvc "${DEPLOYMENT_NAME}-pvc" maven-cache-pvc -n "$PIPELINE_NAMESPACE" 2>/dev/null || true

log "Deleting RBAC..."
kubectl delete rolebinding "${DEPLOYMENT_NAME}-binding" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true
kubectl delete role "${DEPLOYMENT_NAME}-role" -n "$PIPELINE_NAMESPACE" 2>/dev/null || true
kubectl delete rolebinding "${DEPLOYMENT_NAME}-deployer-binding" -n "$DEPLOYMENT_NAMESPACE" 2>/dev/null || true
kubectl delete role "${DEPLOYMENT_NAME}-deployer-role" -n "$DEPLOYMENT_NAMESPACE" 2>/dev/null || true

stage "Destroy Terraform Secrets"
cd "$TERRAFORM_DIR"

if [ -f "terraform.tfvars" ]; then
    terraform destroy -auto-approve
    log "Terraform secrets destroyed."
else
    error "terraform.tfvars not found. Cannot destroy secrets without Terraform config. Run ./installation/init.sh first."
fi

echo ""
echo "=========================================="
echo "  DESTROY COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  All service resources removed."
echo "  Shared infrastructure still running in namespace: ${PIPELINE_NAMESPACE}"
