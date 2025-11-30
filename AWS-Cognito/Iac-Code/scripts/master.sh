#!/bin/bash

set -euo pipefail

#######################################
# Master Orchestrator Script - Simplified
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOGS_DIR}/master-orchestrator.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Logging Functions
#######################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        "INFO")    echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#######################################
# Main Functions
#######################################

# Function 1: Run Terraform Setup
run_terraform_setup() {
    local tfvars_file="$1"
    local terraform_script="${SCRIPT_DIR}/terraform-setup.sh"
    
    log "INFO" "Starting Terraform setup with: $tfvars_file"
    
    # Check if tfvars file exists
    if [[ ! -f "$tfvars_file" ]]; then
        log "ERROR" "Terraform variables file not found: $tfvars_file"
        return 1
    fi
    
    # Check if script exists
    if [[ ! -f "$terraform_script" ]]; then
        log "ERROR" "Terraform script not found: $terraform_script"
        return 1
    fi
    
    # Make script executable
    chmod +x "$terraform_script"
    
    # Execute terraform setup script with tfvars file
    log "INFO" "Executing: $terraform_script $tfvars_file"
    if "$terraform_script" "$tfvars_file"; then
        log "SUCCESS" "Terraform setup completed successfully"
        return 0
    else
        log "ERROR" "Terraform setup failed"
        return 1
    fi
}

# Function 2: Run Cognito User Creation
run_cognito_user_creation() {
    log "INFO" "Starting Cognito user creation process..."
    
    # Get lower_environment flag from terraform outputs
    local create_cognito_user
    create_cognito_user=$(cd "$PROJECT_ROOT" && terraform output -raw "create_cognito_user" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log "WARNING" "Could not retrieve cognito-user flag from Terraform output"
        return 0
    fi
    
    log "INFO" "Execute Cognnito Script flag: $create_cognito_user"
    
    # Only proceed if lower_environment is true
    if [[ "$create_cognito_user" != "true" ]]; then
        log "INFO" "Execute Cognito Script is not enabled. Skipping Cognito user creation."
        return 0
    fi
    e
    log "INFO" "Execute Cognito Script environment enabled. Proceeding with Cognito user creation..."
    
    # Get Cognito user pool ID from terraform outputs
    local user_pool_id
    user_pool_id=$(cd "$PROJECT_ROOT" && terraform output -raw "cognito_user_pool_id" 2>/dev/null)
    if [[ $? -ne 0 || -z "$user_pool_id" ]]; then
        log "ERROR" "Failed to get cognito_user_pool_id from Terraform output"
        return 1
    fi
    
    log "INFO" "Cognito User Pool ID: $user_pool_id"
    
    # Get Cognito user list from terraform outputs
    local cognito_user_list
    cognito_user_list=$(cd "$PROJECT_ROOT" && terraform output -json "cognito_user_list" | jq -r '.[]' | paste -sd "," -)
    echo "${cognito_user_list}"
    if [[ $? -ne 0 || -z "$cognito_user_list" ]]; then
        log "ERROR" "Failed to get cognito_user_list from Terraform output"
        return 1
    fi
    
    log "INFO" "Cognito user list retrieved (raw JSON): $cognito_user_list"
    
    # Get Cognito admin group from terraform outputs
    local cognito_admin_group
    cognito_admin_group=$(cd "$PROJECT_ROOT" && terraform output -raw "cognito_admin_group" 2>/dev/null)
    if [[ $? -ne 0 || -z "$cognito_admin_group" ]]; then
        log "ERROR" "Failed to get cognito_admin_group from Terraform output"
        return 1
    fi
    
    log "INFO" "Cognito admin group: $cognito_admin_group"
    
    # Get AWS region from terraform outputs
    local aws_region
    aws_region=$(cd "$PROJECT_ROOT" && terraform output -raw "aws_region" 2>/dev/null)
    if [[ $? -ne 0 || -z "$aws_region" ]]; then
        log "ERROR" "Failed to get aws_region from Terraform output"
        return 1
    fi
    
    log "INFO" "AWS Region: $aws_region"
    
    # Check if user creation script exists
    local user_create_script="${PROJECT_ROOT}/scripts/cognito-user-create.sh"
    if [[ ! -f "$user_create_script" ]]; then
        log "ERROR" "User creation script not found: $user_create_script"
        return 1
    fi
    
    # Make script executable
    chmod +x "$user_create_script"
    
    # Execute user creation script with AWS region
    log "INFO" "Executing Cognito user creation script..."
    if "$user_create_script" "$user_pool_id" "$cognito_admin_group" "$cognito_user_list" "$aws_region"; then
        log "SUCCESS" "Cognito user creation completed successfully"
        
        # Fetch the log file if it exists
        if [[ -f "/tmp/cognito-user-create.log" ]]; then
            log "INFO" "Copying Cognito user creation log..."
            mkdir -p "${LOGS_DIR}/remote-logs"
            cp /tmp/cognito-user-create.log "${LOGS_DIR}/remote-logs/cognito-user-create.log"
            log "SUCCESS" "Cognito log copied to ${LOGS_DIR}/remote-logs/"
            log "INFO" "Last 10 lines of Cognito user creation log:"
            echo "----------------------------------------"
            tail -10 "${LOGS_DIR}/remote-logs/cognito-user-create.log"
            echo "----------------------------------------"
        fi
        
        return 0
    else
        log "ERROR" "Cognito user creation failed"
        
        # Try to copy logs even on failure
        if [[ -f "/tmp/cognito-user-create.log" ]]; then
            mkdir -p "${LOGS_DIR}/remote-logs"
            cp /tmp/cognito-user-create.log "${LOGS_DIR}/remote-logs/cognito-user-create-error.log"
            log "WARNING" "Error log copied to ${LOGS_DIR}/remote-logs/cognito-user-create-error.log"
        fi
        
        return 1
    fi
}

#######################################
# Main Function
#######################################

main() {
    # Check minimum arguments
    if [[ $# -lt 1 ]]; then
        log "ERROR" "Usage: $0 <environment>"
        exit 1
    fi
    
    local environment="$1"
    
    # Initialize log
    echo "=== Master Orchestrator Log - $(date) ===" > "$LOG_FILE"
    
    # Validate environment
    if [[ -z "$environment" ]]; then
        log "ERROR" "Environment argument is required"
        exit 1
    fi
    
    log "INFO" "Master Orchestrator starting..."
    log "INFO" "Environment: $environment"
    log "INFO" "Working directory: $SCRIPT_DIR"
    
    # Find the single tfvars file in environments folder
    local tfvars_file
    tfvars_file=$(find "${PROJECT_ROOT}/environments" -name "*.tfvars" -type f | head -1)
    
    if [[ -z "$tfvars_file" ]]; then
        log "ERROR" "No .tfvars file found in environments folder"
        exit 1
    fi
    
    log "INFO" "Using tfvars file: $tfvars_file"
    
    # Step 1: Run Terraform setup
    if ! run_terraform_setup "$tfvars_file"; then
        log "ERROR" "Terraform setup failed, exiting"
        exit 1
    fi
    
    # Brief pause between steps
    log "INFO" "Waiting 5 seconds before Cognito user creation..."
    sleep 5
    
    # Step 2: Run Cognito User Creation (conditional)
    if ! run_cognito_user_creation; then
        log "ERROR" "Cognito user creation failed, exiting"
        exit 1
    fi
    
    # Success
    log "SUCCESS" "All operations completed successfully!"
    log "INFO" "Log file: $LOG_FILE"
    
    echo ""
    echo "=== EXECUTION SUMMARY ==="
    echo "✅ Terraform setup: Completed"
    echo "✅ Cognito user creation: Completed"
    echo "✅ Log file: $LOG_FILE"
    echo "✅ Remote logs: ${LOGS_DIR}/remote-logs/"
}

# Handle interrupts
trap 'log "ERROR" "Script interrupted"; exit 130' INT TERM

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi