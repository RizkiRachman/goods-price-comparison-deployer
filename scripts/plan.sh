#!/bin/bash
# Plan: Execute partial Tekton pipeline (clone → build → test only)
# No image build, no deploy. Verifies code compiles and tests pass.
# Assumes infrastructure is already initialized (run ./scripts/init.sh first)
#
# Usage: ./scripts/plan.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source lib + stages
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/stages/pipeline-run.sh"

load_env
set_defaults
check_prerequisites
check_tekton_pipeline

echo ""
echo "=========================================="
echo "  PLAN — Partial Pipeline (Build + Test)"
echo "=========================================="
echo ""
echo "  Service: ${DEPLOYMENT_NAME}"
echo "  Mode:    plan (build + test only, no deploy)"
echo ""

timer_start

stage_pipeline_run "plan"

echo ""
echo "=========================================="
echo "  ✅ PLAN COMPLETE — $(timer_elapsed)"
echo "=========================================="
echo ""
echo "  Build and test passed. No deployment was made."
echo ""
echo "  To deploy:"
echo "    ./scripts/apply.sh"
