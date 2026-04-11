#!/bin/bash
# Stage: Init Infra — initialize Terraform and verify Vault connectivity

stage_init_infra() {
    timer_start
    stage "Init Infra — setting up Terraform + Vault"
    step "Preparing Terraform configuration..."
    cd "$TERRAFORM_DIR"

    # Ensure tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        warn "terraform.tfvars not found."
        if [ -f "terraform.tfvars.example" ]; then
            log "Copying terraform.tfvars.example → terraform.tfvars"
            cp terraform.tfvars.example terraform.tfvars
            warn "Edit terraform/terraform.tfvars with your Vault token before continuing."
            error "Set vault_token in terraform/terraform.tfvars, then re-run."
        else
            error "No terraform.tfvars.example found. Create terraform.tfvars manually."
        fi
    fi

    # Terraform init if needed
    if [ ! -d ".terraform" ]; then
        step "Initializing Terraform providers..."
        terraform init 2>&1 | while IFS= read -r line; do
            if [[ "$line" == *"Installing"* ]] || [[ "$line" == *"Terraform"* ]] || [[ "$line" == *"Error"* ]]; then
                step "$line"
            fi
        done
    else
        step "Terraform already initialized."
    fi

    check_vault
    log "Init complete."
    timer_print
}
