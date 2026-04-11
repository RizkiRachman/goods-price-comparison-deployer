#!/bin/bash
# Stage: Pipeline Run — trigger Tekton PipelineRun and wait for completion
# Usage: stage_pipeline_run "full" or stage_pipeline_run "plan"

stage_pipeline_run() {
    local mode="${1:-full}"
    timer_start

    if [ "$mode" = "full" ]; then
        stage "Pipeline Run — full pipeline (clone → build → test → image → deploy)"
    else
        stage "Pipeline Run — plan mode (clone → build → test only)"
    fi

    step "Pipeline: goods-price-pipeline"
    step "Mode: ${mode}"
    step "Namespace: ${PIPELINE_NAMESPACE}"

    # Set PIPELINE_MODE for envsubst
    export PIPELINE_MODE="$mode"

    # Generate unique run name
    local RUN_NAME="${DEPLOYMENT_NAME}-$(date +%s)"
    step "PipelineRun: ${RUN_NAME}"

    # Create PipelineRun from template
    envsubst "$PIPELINE_RUN_VARS" < "$DEPLOYER_DIR/pipelines/pipeline-run.yaml" | \
        sed "s|generateName: ${DEPLOYMENT_NAME}-|name: ${RUN_NAME}|" | \
        kubectl apply -f - || error "Failed to create PipelineRun"

    log "PipelineRun submitted. Waiting for tasks to execute..."
    echo ""

    # Wait for pipeline completion with progress
    local timeout=600
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local condition=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
        local reason=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Running")

        if [ "$condition" = "Succeeded" ] || [ "$reason" = "Succeeded" ]; then
            printf "\r                                                              \r"
            log "Pipeline completed successfully!"
            break
        elif [ "$condition" = "Failed" ] || [ "$reason" = "Failed" ]; then
            printf "\r                                                              \r"
            local fail_msg=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
                -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "Unknown error")
            echo ""
            error "Pipeline failed: ${fail_msg}"
        fi

        # Show progress spinner
        local char="${_SPINNER_CHARS:$((elapsed % ${#_SPINNER_CHARS})):1}"
        printf "\r  ${CYAN}%s${NC} Waiting... %ds elapsed (status: %s)   " "$char" "$elapsed" "$reason"
        sleep 5
        elapsed=$((elapsed+5))
    done

    printf "\r                                                              \r"

    if [ $elapsed -ge $timeout ]; then
        error "Pipeline timed out after ${timeout}s"
    fi

    # Show task results
    echo ""
    step "Task results:"
    kubectl get taskruns -n "$PIPELINE_NAMESPACE" \
        -l "tekton.dev/pipelineRun=${RUN_NAME}" \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type 2>/dev/null || true

    # Show pipeline logs summary
    echo ""
    step "PipelineRun details:"
    kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type,START:.status.startTime,COMPLETION:.status.completionTime 2>/dev/null || true

    timer_print
}
