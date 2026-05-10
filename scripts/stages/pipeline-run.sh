#!/bin/bash
# Stage: Pipeline Run — trigger a Tekton PipelineRun and wait for completion.
# Functions:
#   stage_pipeline_run         — full CI/CD pipeline (main branch)
#   stage_security_pipeline_run — SAST + DAST only (non-main branches)

stage_pipeline_run() {
    local template="$DEPLOYER_DIR/pipelines/pipeline-plan-apply.yaml"

    if [ ! -f "$template" ]; then
        error "PipelineRun template not found: ${template}"
    fi

    timer_start

    if [ "$PIPELINE_MODE" = "cloud" ]; then
        stage "Pipeline Run (clone → build → test → db → config → deploy → gravitee) [cloud]"
    else
        stage "Pipeline Run (clone → build → test → image → db → config → deploy → gravitee) [local]"
    fi

    step "Pipeline: ${DEPLOYMENT_NAME}-pipeline"
    step "Namespace: ${PIPELINE_NAMESPACE}"

    local RUN_NAME="${DEPLOYMENT_NAME}-$(date +%s)"
    step "PipelineRun: ${RUN_NAME}"

    envsubst "$PIPELINE_RUN_VARS" < "$template" \
        | sed "s|generateName: ${DEPLOYMENT_NAME}-[^$]*|name: ${RUN_NAME}|" \
        | kubectl apply -f - \
        || error "Failed to create PipelineRun"

    log "PipelineRun submitted. Waiting for tasks to execute..."
    echo ""

    local timeout=600
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local condition reason
        condition=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
        reason=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Running")

        if [ "$condition" = "Succeeded" ] || [ "$reason" = "Succeeded" ]; then
            printf "\r                                                              \r"
            log "Pipeline completed successfully!"
            break
        elif [ "$condition" = "Failed" ] || [ "$reason" = "Failed" ]; then
            printf "\r                                                              \r"
            local fail_msg
            fail_msg=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
                -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "Unknown error")
            echo ""
            error "Pipeline failed: ${fail_msg}"
        fi

        local char="${_SPINNER_CHARS:$((elapsed % ${#_SPINNER_CHARS})):1}"
        printf "\r  ${CYAN}%s${NC} Waiting... %ds elapsed (status: %s)   " "$char" "$elapsed" "$reason"
        sleep 5
        elapsed=$((elapsed+5))
    done

    printf "\r                                                              \r"

    if [ $elapsed -ge $timeout ]; then
        error "Pipeline timed out after ${timeout}s"
    fi

    echo ""
    step "Task results:"
    kubectl get taskruns -n "$PIPELINE_NAMESPACE" \
        -l "tekton.dev/pipelineRun=${RUN_NAME}" \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type 2>/dev/null || true

    echo ""
    step "PipelineRun details:"
    kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type,START:.status.startTime,COMPLETION:.status.completionTime \
        2>/dev/null || true

    timer_print
}

stage_security_pipeline_run() {
    local template="$DEPLOYER_DIR/pipelines/pipeline-security-run.yaml"
    local branch="${1:-${GIT_REPO_DEFAULT_BRANCH}}"

    if [ ! -f "$template" ]; then
        error "Security PipelineRun template not found: ${template}"
    fi

    timer_start

    stage "Security Pipeline (clone → build → test → sast → dast)"

    step "Pipeline:  ${DEPLOYMENT_NAME}-security-pipeline"
    step "Namespace: ${PIPELINE_NAMESPACE}"
    step "Branch:    ${branch}"

    local RUN_NAME="${DEPLOYMENT_NAME}-security-$(date +%s)"
    step "PipelineRun: ${RUN_NAME}"

    GIT_REPO_DEFAULT_BRANCH="${branch}" \
    envsubst "$SECURITY_RUN_VARS" < "$template" \
        | sed "s|generateName: ${DEPLOYMENT_NAME}-security-[^$]*|name: ${RUN_NAME}|" \
        | kubectl apply -f - \
        || error "Failed to create security PipelineRun"

    log "Security PipelineRun submitted. Waiting..."
    echo ""

    local timeout=1800
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local condition reason
        condition=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
        reason=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Running")

        if [ "$condition" = "Succeeded" ] || [ "$reason" = "Succeeded" ]; then
            printf "\r                                                              \r"
            log "Security pipeline completed successfully!"
            break
        elif [ "$condition" = "Failed" ] || [ "$reason" = "Failed" ]; then
            printf "\r                                                              \r"
            local fail_msg
            fail_msg=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
                -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "Unknown error")
            echo ""
            error "Security pipeline failed: ${fail_msg}"
        fi

        local char="${_SPINNER_CHARS:$((elapsed % ${#_SPINNER_CHARS})):1}"
        printf "\r  ${CYAN}%s${NC} Waiting... %ds elapsed (status: %s)   " "$char" "$elapsed" "$reason"
        sleep 5
        elapsed=$((elapsed+5))
    done

    printf "\r                                                              \r"

    if [ $elapsed -ge $timeout ]; then
        error "Security pipeline timed out after ${timeout}s"
    fi

    echo ""
    step "Task results:"
    kubectl get taskruns -n "$PIPELINE_NAMESPACE" \
        -l "tekton.dev/pipelineRun=${RUN_NAME}" \
        -o custom-columns=TASK:.metadata.labels.tekton\\.dev/pipelineTask,STATUS:.status.conditions[0].reason \
        2>/dev/null || true

    timer_print
}

stage_production_pipeline_run() {
    local template="$DEPLOYER_DIR/pipelines/pipeline-plan-apply-production.yaml"

    if [ ! -f "$template" ]; then
        error "Production PipelineRun template not found: ${template}"
    fi

    timer_start

    stage "Production Pipeline Run (external database)"
    echo ""
    echo "  Database host: ${DATABASE_HOST:-${POSTGRES_HOST}}"
    echo "  Database port: ${DATABASE_PORT:-${POSTGRES_PORT}}"
    echo "  Source: ${DATABASE_HOST:+external DATABASE_HOST}${DATABASE_HOST:-local POSTGRES_HOST}"
    echo ""

    step "Pipeline: ${DEPLOYMENT_NAME}-pipeline"
    step "Namespace: ${PIPELINE_NAMESPACE}"

    local RUN_NAME="${DEPLOYMENT_NAME}-production-$(date +%s)"
    step "PipelineRun: ${RUN_NAME}"

    envsubst "$PIPELINE_RUN_VARS" < "$template" \
        | sed "s|generateName: ${DEPLOYMENT_NAME}-production-[^$]*|name: ${RUN_NAME}|" \
        | kubectl apply -f - \
        || error "Failed to create production PipelineRun"

    log "Production PipelineRun submitted. Waiting for tasks to execute..."
    echo ""

    local timeout=600
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local condition reason
        condition=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
        reason=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
            -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Running")

        if [ "$condition" = "Succeeded" ] || [ "$reason" = "Succeeded" ]; then
            printf "\r                                                              \r"
            log "Production pipeline completed successfully!"
            break
        elif [ "$condition" = "Failed" ] || [ "$reason" = "Failed" ]; then
            printf "\r                                                              \r"
            local fail_msg
            fail_msg=$(kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
                -o jsonpath='{.status.conditions[0].message}' 2>/dev/null || echo "Unknown error")
            echo ""
            error "Production pipeline failed: ${fail_msg}"
        fi

        local char="${_SPINNER_CHARS:$((elapsed % ${#_SPINNER_CHARS})):1}"
        printf "\r  ${CYAN}%s${NC} Waiting... %ds elapsed (status: %s)   " "$char" "$elapsed" "$reason"
        sleep 5
        elapsed=$((elapsed+5))
    done

    printf "\r                                                              \r"

    if [ $elapsed -ge $timeout ]; then
        error "Production pipeline timed out after ${timeout}s"
    fi

    echo ""
    step "Task results:"
    kubectl get taskruns -n "$PIPELINE_NAMESPACE" \
        -l "tekton.dev/pipelineRun=${RUN_NAME}" \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type 2>/dev/null || true

    echo ""
    step "PipelineRun details:"
    kubectl get pipelinerun "$RUN_NAME" -n "$PIPELINE_NAMESPACE" \
        -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].type,START:.status.startTime,COMPLETION:.status.completionTime \
        2>/dev/null || true

    timer_print
}