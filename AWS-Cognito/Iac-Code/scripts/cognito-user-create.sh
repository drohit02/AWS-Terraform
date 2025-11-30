#!/bin/bash
set -euo pipefail

#######################################
# Cognito User Creation Script
# Usage: ./cognito-user-create.sh <user_pool_id> <cognito_admin_group> <user_list_comma_separated> <aws_region>
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/cognito-user-create.log"
: > "$LOG_FILE"  # clear existing log

# Colors for pretty printing
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Logging function
#######################################
log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)    echo -e "${BLUE}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#######################################
# Temporary Password Generation
#######################################
generate_temp_password() {
    local uppercase="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local lowercase="abcdefghijklmnopqrstuvwxyz"
    local numbers="0123456789"
    local special="!@#$%^&*"
    local password=""

    password+="${uppercase:RANDOM%${#uppercase}:1}"
    password+="${lowercase:RANDOM%${#lowercase}:1}"
    password+="${numbers:RANDOM%${#numbers}:1}"
    password+="${special:RANDOM%${#special}:1}"

    local all_chars="${uppercase}${lowercase}${numbers}${special}"
    for i in {1..8}; do
        password+="${all_chars:RANDOM%${#all_chars}:1}"
    done

    echo "$password" | fold -w1 | shuf | tr -d '\n'
}

#######################################
# Validate arguments
#######################################
if [[ $# -ne 4 ]]; then
    log "ERROR" "Usage: $0 <user_pool_id> <cognito_admin_group> <user_list_comma_separated> <aws_region>"
    exit 1
fi

USER_POOL_ID="$1"
COGNITO_GROUP="$2"
USER_LIST="$3"
AWS_REGION="$4"

log "INFO" "Starting Cognito user creation process..."
log "INFO" "User Pool ID: $USER_POOL_ID"
log "INFO" "Cognito Group: $COGNITO_GROUP"
log "INFO" "AWS Region: $AWS_REGION"

#######################################
# Step 1: Verify user pool existence
#######################################
if ! aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "ERROR" "User Pool ID '$USER_POOL_ID' does not exist in region '$AWS_REGION'"
    exit 1
else
    log "SUCCESS" "Verified Cognito User Pool exists: $USER_POOL_ID"
fi

#######################################
# Step 2: Loop through users and create
#######################################
IFS=',' read -r -a users <<< "$USER_LIST"

for user_email in "${users[@]}"; do
    user_email=$(echo "$user_email" | xargs)

    if [[ -z "$user_email" ]]; then
        log "WARNING" "Skipping empty user entry"
        continue
    fi

    log "INFO" "Processing user: $user_email"

    # Check if user already exists
    if aws cognito-idp admin-get-user \
        --user-pool-id "$USER_POOL_ID" \
        --username "$user_email" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log "INFO" "User '$user_email' already exists. Skipping creation."
    else
        # Generate temporary password
        temp_password=$(generate_temp_password)
        log "INFO" "Generated temporary password for '$user_email'"

        # Create user in Cognito
        if aws cognito-idp admin-create-user \
            --user-pool-id "$USER_POOL_ID" \
            --username "$user_email" \
            --user-attributes Name=email,Value="$user_email" Name=email_verified,Value=true \
            --temporary-password "$temp_password" \
            --desired-delivery-mediums EMAIL \
            --region "$AWS_REGION" >/tmp/create-user-output.json 2>&1; then
            log "SUCCESS" "User created: $user_email"
        else
            log "ERROR" "Failed to create user: $user_email. See /tmp/create-user-output.json for details."
            continue
        fi
    fi

    # Check if user already in group
    if aws cognito-idp admin-list-groups-for-user \
        --user-pool-id "$USER_POOL_ID" \
        --username "$user_email" \
        --region "$AWS_REGION" | grep -q "\"GroupName\": \"$COGNITO_GROUP\""; then
        log "INFO" "User '$user_email' already in group '$COGNITO_GROUP'. Skipping group assignment."
    else
        # Add user to group
        if aws cognito-idp admin-add-user-to-group \
            --user-pool-id "$USER_POOL_ID" \
            --username "$user_email" \
            --group-name "$COGNITO_GROUP" \
            --region "$AWS_REGION" >/dev/null 2>&1; then
            log "SUCCESS" "User '$user_email' added to group '$COGNITO_GROUP'"
        else
            log "ERROR" "Failed to add user '$user_email' to group '$COGNITO_GROUP'"
        fi
    fi
done

log "SUCCESS" "Cognito user creation process completed successfully."
log "INFO" "Full log stored at: $LOG_FILE"
exit 0
