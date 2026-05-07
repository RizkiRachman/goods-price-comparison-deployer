#!/bin/bash
# Clean: Remove pipeline run history and orphaned task run pods.
# Does NOT delete pipelines, tasks, or active deployments.
#
# Usage: ./scripts/clean.sh [options]
#
# Options:
#   --failed             Delete only failed/cancelled runs (default)
#   --all                Delete all completed runs (succeeded + failed)
#   --keep-last <N>      Keep the N most recent runs per mode (default: 3)
#   --older-than <days>  Only delete runs older than N days
#   --dry-run            Show what would be deleted without deleting
#   --yes                Skip confirmation prompt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/k8s.sh"

load_env
set_defaults
check_prerequisites

# ── Defaults ──────────────────────────────────────────────
MODE="failed"
KEEP_LAST=3
OLDER_THAN_DAYS=""
DRY_RUN=false
SKIP_CONFIRM=false

# ── Arg parsing ───────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)        MODE="all";    shift ;;
        --failed)     MODE="failed"; shift ;;
        --keep-last)  KEEP_LAST="$2"; shift 2 ;;
        --older-than) OLDER_THAN_DAYS="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true;  shift ;;
        --yes)        SKIP_CONFIRM=true; shift ;;
        *)
            echo "Usage: $0 [--all|--failed] [--keep-last N] [--older-than days] [--dry-run] [--yes]"
            exit 1 ;;
    esac
done

PIPELINE_LABEL="tekton.dev/pipeline=${DEPLOYMENT_NAME}-pipeline"

echo ""
echo "=========================================="
echo "  CLEAN — Pipeline Run History"
echo "=========================================="
echo ""
echo "  Namespace:  ${PIPELINE_NAMESPACE}"
echo "  Pipeline:   ${DEPLOYMENT_NAME}-pipeline"
echo "  Mode:       ${MODE}"
echo "  Keep last:  ${KEEP_LAST}"
[ -n "${OLDER_THAN_DAYS}" ] && echo "  Older than: ${OLDER_THAN_DAYS} days"
[ "${DRY_RUN}" = true ]     && echo "  Dry run:    yes (nothing will be deleted)"
echo ""

timer_start

# ── Cutoff timestamp ──────────────────────────────────────
CUTOFF_EPOCH=""
if [ -n "${OLDER_THAN_DAYS}" ]; then
    CUTOFF_EPOCH=$(date -v-${OLDER_THAN_DAYS}d +%s 2>/dev/null \
        || date -d "-${OLDER_THAN_DAYS} days" +%s 2>/dev/null || true)
    if [ -z "${CUTOFF_EPOCH}" ]; then
        error "Could not calculate cutoff date. Check your 'date' command."
    fi
fi

# ── Fetch all PipelineRuns as JSON ────────────────────────
stage "Fetching PipelineRuns"
ALL_JSON=$(kubectl get pipelineruns -n "${PIPELINE_NAMESPACE}" \
    -l "${PIPELINE_LABEL}" -o json 2>/dev/null || true)

TOTAL=$(echo "${ALL_JSON}" | jq '.items | length')
log "Found ${TOTAL} PipelineRun(s) for pipeline '${DEPLOYMENT_NAME}-pipeline'"

if [ "${TOTAL}" -eq 0 ]; then
    echo ""
    log "Nothing to clean."
    exit 0
fi

# Print current state
echo ""
echo "  Current history:"
echo "  ┌──────────────────────────────────────────────┬─────────────┬──────────────────────┐"
printf "  │ %-44s │ %-11s │ %-20s │\n" "NAME" "RESULT" "CREATED"
echo "  ├──────────────────────────────────────────────┼─────────────┼──────────────────────┤"
echo "${ALL_JSON}" | jq -r '
  .items
  | sort_by(.metadata.creationTimestamp)
  | reverse[]
  | [
      .metadata.name,
      ((.status.conditions[]? | select(.type=="Succeeded")) |
        if .status == "True"    then "Succeeded"
        elif .status == "False" then (.reason // "Failed")
        else "Running"
        end) // "Unknown",
      (.metadata.creationTimestamp | split("T")[0])
    ]
  | @tsv
' | while IFS=$'\t' read -r name result created; do
    printf "  │ %-44s │ %-11s │ %-20s │\n" "${name}" "${result}" "${created}"
done
echo "  └──────────────────────────────────────────────┴─────────────┴──────────────────────┘"
echo ""

# ── Build delete list via jq ──────────────────────────────
# Sort newest-first so --keep-last N skips the first N in the target group.
CANDIDATES=$(echo "${ALL_JSON}" | jq -r \
    --arg mode "${MODE}" \
    --argjson keep "${KEEP_LAST}" \
    --argjson cutoff "${CUTOFF_EPOCH:-0}" \
    '
    .items
    | sort_by(.metadata.creationTimestamp) | reverse
    | map(
        . as $pr |
        ($pr.status.conditions[]? | select(.type=="Succeeded")) as $cond |
        {
          name:    $pr.metadata.name,
          created: $pr.metadata.creationTimestamp,
          epoch:   ($pr.metadata.creationTimestamp | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime),
          result:  (if $cond.status == "True"    then "Succeeded"
                    elif $cond.status == "False" then ($cond.reason // "Failed")
                    else "Running" end)
        }
    )
    # exclude currently running
    | map(select(.result != "Running"))
    # apply mode filter
    | if $mode == "failed" then
        map(select(.result != "Succeeded"))
      else . end
    # apply --older-than filter
    | if $cutoff > 0 then map(select(.epoch < $cutoff)) else . end
    # apply --keep-last: skip first $keep items (they are the newest)
    | if $keep > 0 then .[$keep:] else . end
    | .[].name
' 2>/dev/null || true)

if [ -z "${CANDIDATES}" ]; then
    log "No PipelineRuns match the deletion criteria (keep-last=${KEEP_LAST}, mode=${MODE})."
    exit 0
fi

COUNT=$(echo "${CANDIDATES}" | wc -l | tr -d ' ')

echo "  PipelineRuns to delete (${COUNT}):"
echo "  ┌──────────────────────────────────────────────┐"
for name in ${CANDIDATES}; do
    printf "  │  %-43s │\n" "${name}"
done
echo "  └──────────────────────────────────────────────┘"
echo ""

if [ "${DRY_RUN}" = true ]; then
    log "Dry run — nothing deleted. Remove --dry-run to apply."
    exit 0
fi

if [ "${SKIP_CONFIRM}" = false ]; then
    read -rp "  Delete ${COUNT} PipelineRun(s)? (yes/no): " confirm
    if [ "${confirm}" != "yes" ]; then
        log "Aborted."
        exit 0
    fi
fi

stage "Deleting PipelineRuns"
DELETED=0
for name in ${CANDIDATES}; do
    if kubectl delete pipelinerun "${name}" -n "${PIPELINE_NAMESPACE}" --ignore-not-found 2>/dev/null; then
        log "  Deleted: ${name}"
        DELETED=$((DELETED + 1))
    else
        warn "  Could not delete: ${name}"
    fi
done

# ── Orphaned TaskRuns ─────────────────────────────────────
stage "Checking for orphaned TaskRuns"
ORPHANS=$(kubectl get taskruns -n "${PIPELINE_NAMESPACE}" \
    -l "${PIPELINE_LABEL}" -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.ownerReferences == null or (.metadata.ownerReferences | length) == 0) | .metadata.name' || true)

if [ -n "${ORPHANS}" ]; then
    ORPHAN_COUNT=$(echo "${ORPHANS}" | wc -l | tr -d ' ')
    warn "  Found ${ORPHAN_COUNT} orphaned TaskRun(s) (no owning PipelineRun)"
    for name in ${ORPHANS}; do
        if [ "${DRY_RUN}" = false ]; then
            kubectl delete taskrun "${name}" -n "${PIPELINE_NAMESPACE}" --ignore-not-found 2>/dev/null && \
                log "  Deleted orphan: ${name}" || warn "  Could not delete: ${name}"
        else
            log "  Would delete orphan: ${name}"
        fi
    done
else
    log "  No orphaned TaskRuns found."
fi

# ── Prune unused containerd images inside k3d node ───────
stage "Pruning unused containerd images (k3d node)"
K3D_NODE=$(docker ps --filter name=k3d-dev-infra-server --format '{{.Names}}' | head -1)

if [ -z "${K3D_NODE}" ]; then
    warn "  k3d server node not found — skipping image prune."
else
    echo "  Node: ${K3D_NODE}"

    # Show disk usage before
    BEFORE=$(docker exec "${K3D_NODE}" df -h / 2>/dev/null | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}')
    echo "  Disk before: ${BEFORE}"

    # Count unused images
    UNUSED_IMAGES=$(docker exec "${K3D_NODE}" crictl images 2>/dev/null | awk 'NR>1 && $3=="<none>" {print $1":"$2}' || true)
    UNUSED_COUNT=$(echo "${UNUSED_IMAGES}" | grep -c . || true)

    if [ "${UNUSED_COUNT}" -gt 0 ] && [ -n "${UNUSED_IMAGES}" ]; then
        echo "  Found ${UNUSED_COUNT} untagged image layer(s) to prune"
        if [ "${DRY_RUN}" = true ]; then
            log "  Dry run — skipping prune."
        else
            if docker exec "${K3D_NODE}" crictl rmi --prune 2>/dev/null; then
                log "  Image prune complete."
            else
                warn "  Image prune had errors (non-fatal)."
            fi

            AFTER=$(docker exec "${K3D_NODE}" df -h / 2>/dev/null | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}')
            echo "  Disk after:  ${AFTER}"
        fi
    else
        log "  No unused images to prune."
    fi

    # Remove exited/dead containers left by completed pods
    DEAD=$(docker exec "${K3D_NODE}" crictl ps -a --state=Exited -o json 2>/dev/null \
        | jq -r '.containers[].id' 2>/dev/null || true)
    if [ -n "${DEAD}" ]; then
        DEAD_COUNT=$(echo "${DEAD}" | grep -c . || true)
        echo "  Found ${DEAD_COUNT} exited container(s) from completed pods"
        if [ "${DRY_RUN}" = false ]; then
            for cid in ${DEAD}; do
                docker exec "${K3D_NODE}" crictl rm "${cid}" 2>/dev/null || true
            done
            log "  Exited containers removed."
        else
            log "  Dry run — skipping container removal."
        fi
    else
        log "  No exited containers to remove."
    fi
fi

echo ""
echo "=========================================="
echo "  CLEAN COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Deleted: ${DELETED} PipelineRun(s)"
echo "  Active pipelines, tasks, and deployments preserved."
echo ""
echo "  Tip: to auto-clean on every run:"
echo "    ./scripts/clean.sh --failed --keep-last 5 --yes"
echo ""
