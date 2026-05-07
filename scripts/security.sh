#!/bin/bash
# Security: run SAST (OWASP Dependency-Check) + DAST (ZAP) against the deployed service.
# Intended for non-main branches — does NOT build image or deploy.
# The service must already be running (deploy via ./scripts/apply.sh first).
#
# Usage: ./scripts/security.sh [--branch <branch>] [--cvss <score>] [--risk <level>]
#
# Options:
#   --branch <name>   Git branch to scan (default: current git branch)
#   --cvss <score>    SAST: fail on CVE CVSS >= score (default: 7)
#   --risk <level>    DAST: fail on ZAP risk >= level 0-3 (default: 2 = Medium)
#   --sast-only       Skip DAST scan
#   --dast-only       Skip SAST scan (run build+test still)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/k8s.sh"
source "$SCRIPT_DIR/stages/pipeline-run.sh"

load_env
set_defaults
check_prerequisites

# ── Args ──────────────────────────────────────────────────
BRANCH=$(git -C "$(dirname "$SCRIPT_DIR")" rev-parse --abbrev-ref HEAD 2>/dev/null \
    || echo "${GIT_REPO_DEFAULT_BRANCH}")
SAST_ONLY=false
DAST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)  BRANCH="$2"; shift 2 ;;
        --cvss)    SAST_FAIL_ON_CVSS="$2"; shift 2 ;;
        --risk)    DAST_FAIL_ON_RISK="$2"; shift 2 ;;
        --sast-only) SAST_ONLY=true; shift ;;
        --dast-only) DAST_ONLY=true; shift ;;
        *)
            echo "Usage: $0 [--branch <name>] [--cvss <score>] [--risk <level>] [--sast-only|--dast-only]"
            exit 1 ;;
    esac
done

export SAST_FAIL_ON_CVSS DAST_FAIL_ON_RISK

echo ""
echo "=========================================="
echo "  SECURITY — SAST + DAST"
echo "=========================================="
echo ""
echo "  Service:      ${DEPLOYMENT_NAME}"
echo "  Branch:       ${BRANCH}"
echo "  SAST CVSS >=: ${SAST_FAIL_ON_CVSS} (fail threshold)"
echo "  DAST risk >=: ${DAST_FAIL_ON_RISK} (0=Info 1=Low 2=Medium 3=High)"
echo "  DAST target:  http://${DEPLOYMENT_NAME}.${DEPLOYMENT_NAMESPACE}.svc.cluster.local:${DEPLOYMENT_PORT}"
echo ""

# Guard: warn if running on main
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    warn "Running security scan on '${BRANCH}' — consider using ./scripts/apply.sh for main."
    read -rp "  Continue anyway? (yes/no): " _confirm
    [ "$_confirm" = "yes" ] || { log "Aborted."; exit 0; }
fi

# Guard: service must be deployed
if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${DEPLOYMENT_NAMESPACE}" &>/dev/null; then
    error "Service '${DEPLOYMENT_NAME}' is not deployed. Run ./scripts/apply.sh first."
fi
READY=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${DEPLOYMENT_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "${READY:-0}" -eq 0 ]; then
    error "Service '${DEPLOYMENT_NAME}' has no ready pods. Wait for deploy to complete."
fi

stage_security_pipeline_run "${BRANCH}"

echo ""
echo "=========================================="
echo "  SECURITY COMPLETE"
echo "=========================================="
echo ""
echo "  ZAP report: check PipelineRun workspace at"
echo "    zap-reports/zap-report.html"
echo ""
