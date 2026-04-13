#!/bin/bash
# Clean: Remove failed/error pipeline runs and unused resources
# Does NOT delete pipelines, tasks, or active deployments
#
# Usage: ./scripts/clean.sh [options]
# Options:
#   --all       Clean all pipeline runs (including succeeded)
#   --failed    Clean only failed/error pipeline runs (default)
#   --older-than <days>  Clean pipeline runs older than N days

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib
source "$SCRIPT_DIR/lib/common.sh"

load_env
set_defaults
check_prerequisites

PIPELINE_NAMESPACE="${PIPELINE_NAMESPACE:-tekton-pipelines}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-goods-price-service}"

# Parse arguments
CLEAN_ALL=false
CLEAN_FAILED=true
OLDER_THAN_DAYS=""
DRY_RUN=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEAN_ALL=true
            CLEAN_FAILED=false
            shift
            ;;
        --failed)
            CLEAN_FAILED=true
            CLEAN_ALL=false
            shift
            ;;
        --older-than)
            OLDER_THAN_DAYS="$2"
            shift 2
            ;;
        --yes)
            DRY_RUN=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--all|--failed] [--older-than <days>] [--yes]"
            echo "  --yes       Skip confirmation and delete immediately"
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  CLEAN — Remove Pipeline Runs & Unused Resources"
echo "=========================================="
echo ""
echo "  Namespace: ${PIPELINE_NAMESPACE}"
echo "  Mode: $([ "$CLEAN_ALL" = true ] && echo "All pipeline runs" || echo "Failed/Error pipeline runs only")"
[ -n "$OLDER_THAN_DAYS" ] && echo "  Age filter: older than ${OLDER_THAN_DAYS} days"
echo ""

timer_start

# Function to clean pipeline runs by condition
clean_pipelineruns() {
    local condition="$1"
    local label_selector=""
    
    if [ -n "$OLDER_THAN_DAYS" ]; then
        # Calculate cutoff time
        local cutoff_time=$(date -v-${OLDER_THAN_DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "-${OLDER_THAN_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
        if [ -z "$cutoff_time" ]; then
            error "Failed to calculate cutoff time. Check your date command."
        fi
        label_selector="--field-selector=metadata.creationTimestamp<${cutoff_time}"
    fi
    
    stage "Clean PipelineRuns — ${condition}"
    
    local pipelineruns
    pipelineruns=$(kubectl get pipelineruns -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipeline=${DEPLOYMENT_NAME}-pipeline $label_selector -o name 2>/dev/null || true)
    
    if [ -z "$pipelineruns" ]; then
        log "No pipeline runs found matching criteria."
        return
    fi
    
    # Collect pipeline runs to delete
    local to_delete=()
    for pr in $pipelineruns; do
        local pr_name=$(echo "$pr" | cut -d'/' -f2)
        local status=$(kubectl get pipelinerun "$pr_name" -n "$PIPELINE_NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
        local start_time=$(kubectl get pipelinerun "$pr_name" -n "$PIPELINE_NAMESPACE" -o jsonpath='{.status.startTime}' 2>/dev/null || echo "N/A")
        local duration=$(kubectl get pipelinerun "$pr_name" -n "$PIPELINE_NAMESPACE" -o jsonpath='{.status.conditions[0].lastTransitionTime}' 2>/dev/null || echo "N/A")
        
        if [ "$condition" = "all" ] || [ "$status" = "Failed" ] || [ "$status" = "Error" ]; then
            to_delete+=("$pr_name|$status|$start_time")
        fi
    done
    
    if [ ${#to_delete[@]} -eq 0 ]; then
        log "No pipeline runs match the deletion criteria."
        return
    fi
    
    # Display what will be deleted
    echo ""
    echo "  Pipeline runs to be deleted:"
    echo "  ┌────────────────────────────────────────────────────────────────────────────┐"
    printf "  │ %-40s │ %-10s │ %-19s │\n" "NAME" "STATUS" "START TIME"
    echo "  ├────────────────────────────────────────────────────────────────────────────┤"
    for item in "${to_delete[@]}"; do
        local name=$(echo "$item" | cut -d'|' -f1)
        local status=$(echo "$item" | cut -d'|' -f2)
        local start_time=$(echo "$item" | cut -d'|' -f3 | cut -d'T' -f1)
        printf "  │ %-40s │ %-10s │ %-19s │\n" "$name" "$status" "$start_time"
    done
    echo "  └────────────────────────────────────────────────────────────────────────────┘"
    echo "  Total: ${#to_delete[@]} pipeline run(s)"
    echo ""
    
    # Ask for confirmation unless --yes flag is set
    if [ "$DRY_RUN" = true ]; then
        read -p "  Delete these pipeline runs? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log "Skipping pipeline run deletion."
            return
        fi
    fi
    
    # Delete the pipeline runs
    local count=0
    for item in "${to_delete[@]}"; do
        local name=$(echo "$item" | cut -d'|' -f1)
        kubectl delete pipelinerun "$name" -n "$PIPELINE_NAMESPACE" 2>/dev/null && \
        log "  Deleted: $name" && \
        count=$((count+1))
    done
    
    log "Deleted $count pipeline run(s)."
}

# Function to clean orphaned task runs (not associated with any pipeline run)
clean_orphaned_taskruns() {
    stage "Clean Orphaned TaskRuns"
    
    # Get all task runs for our pipeline
    local all_taskruns
    all_taskruns=$(kubectl get taskruns -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipeline=${DEPLOYMENT_NAME}-pipeline -o name 2>/dev/null || true)
    
    if [ -z "$all_taskruns" ]; then
        log "No task runs found."
        return
    fi
    
    # Collect orphaned task runs
    local to_delete=()
    for tr in $all_taskruns; do
        local tr_name=$(echo "$tr" | cut -d'/' -f2)
        local owner_ref=$(kubectl get taskrun "$tr_name" -n "$PIPELINE_NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
        local status=$(kubectl get taskrun "$tr_name" -n "$PIPELINE_NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
        
        # Mark for deletion if no owner reference (orphaned)
        if [ -z "$owner_ref" ]; then
            to_delete+=("$tr_name|$status")
        fi
    done
    
    if [ ${#to_delete[@]} -eq 0 ]; then
        log "No orphaned task runs found."
        return
    fi
    
    # Display what will be deleted
    echo ""
    echo "  Orphaned task runs to be deleted:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    printf "  │ %-45s │ %-10s │\n" "NAME" "STATUS"
    echo "  ├──────────────────────────────────────────────────────────┤"
    for item in "${to_delete[@]}"; do
        local name=$(echo "$item" | cut -d'|' -f1)
        local status=$(echo "$item" | cut -d'|' -f2)
        printf "  │ %-45s │ %-10s │\n" "$name" "$status"
    done
    echo "  └──────────────────────────────────────────────────────────┘"
    echo "  Total: ${#to_delete[@]} orphaned task run(s)"
    echo ""
    
    # Ask for confirmation unless --yes flag is set
    if [ "$DRY_RUN" = true ]; then
        read -p "  Delete these orphaned task runs? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log "Skipping orphaned task run deletion."
            return
        fi
    fi
    
    # Delete the orphaned task runs
    local count=0
    for item in "${to_delete[@]}"; do
        local name=$(echo "$item" | cut -d'|' -f1)
        kubectl delete taskrun "$name" -n "$PIPELINE_NAMESPACE" 2>/dev/null && \
        log "  Deleted orphaned: $name" && \
        count=$((count+1))
    done
    
    log "Deleted $count orphaned task run(s)."
}

# Function to clean completed pods from pipeline runs
clean_completed_pods() {
    stage "Clean Completed Pods"
    
    local pods
    pods=$(kubectl get pods -n "$PIPELINE_NAMESPACE" -l tekton.dev/pipelineTask -o name 2>/dev/null || true)
    
    if [ -z "$pods" ]; then
        log "No pipeline pods found."
        return
    fi
    
    # Collect completed/failed pods
    local to_delete=()
    for pod in $pods; do
        local pod_name=$(echo "$pod" | cut -d'/' -f2)
        local phase=$(kubectl get pod "$pod_name" -n "$PIPELINE_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        
        # Mark for deletion if completed or failed
        if [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ]; then
            to_delete+=("$pod_name|$phase")
        fi
    done
    
    if [ ${#to_delete[@]} -eq 0 ]; then
        log "No completed/failed pods found."
        return
    fi
    
    # Display what will be deleted
    echo ""
    echo "  Completed/failed pods to be deleted:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    printf "  │ %-45s │ %-10s │\n" "NAME" "PHASE"
    echo "  ├──────────────────────────────────────────────────────────┤"
    for item in "${to_delete[@]}"; do
        local name=$(echo "$item" | cut -d'|' -f1)
        local phase=$(echo "$item" | cut -d'|' -f2)
        printf "  │ %-45s │ %-10s │\n" "$name" "$phase"
    done
    echo "  └──────────────────────────────────────────────────────────┘"
    echo "  Total: ${#to_delete[@]} pod(s)"
    echo ""
    
    # Ask for confirmation unless --yes flag is set
    if [ "$DRY_RUN" = true ]; then
        read -p "  Delete these completed/failed pods? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log "Skipping pod deletion."
            return
        fi
    fi
    
    # Delete the pods
    local count=0
    for item in "${to_delete[@]}"; do
        local name=$(echo "$item" | cut -d'|' -f1)
        kubectl delete pod "$name" -n "$PIPELINE_NAMESPACE" 2>/dev/null && \
        log "  Deleted: $name" && \
        count=$((count+1))
    done
    
    log "Deleted $count completed pod(s)."
}

# Main cleanup logic
if [ "$CLEAN_ALL" = true ]; then
    clean_pipelineruns "all"
else
    clean_pipelineruns "failed"
fi

clean_orphaned_taskruns
clean_completed_pods

echo ""
echo "=========================================="
echo "  ✅ CLEAN COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Pipeline runs and unused resources cleaned."
echo "  Active pipelines, tasks, and deployments preserved."
echo ""
