#!/bin/bash
# Coder API authentication and helper functions
# Provides authenticated API calls to Coder

set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

if [[ -f "$WORKSPACE_ROOT/.env" ]]; then
    set -a
    source "$WORKSPACE_ROOT/.env"
    set +a
fi

# API Configuration
CODER_URL="${CODER_ACCESS_URL:-http://localhost:7080}"
CODER_TOKEN="${CODER_SESSION_TOKEN:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if Coder token is configured
check_token() {
    if [[ -z "$CODER_TOKEN" ]]; then
        log_error "CODER_SESSION_TOKEN not set in .env"
        log_info "Please complete Coder setup first:"
        log_info "  1. Access Coder at $CODER_URL"
        log_info "  2. Create your admin account"
        log_info "  3. Go to Settings → Tokens"
        log_info "  4. Create a new API token"
        log_info "  5. Add to .env: CODER_SESSION_TOKEN=<your-token>"
        return 1
    fi
    return 0
}

# Make authenticated API call
coder_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    if ! check_token; then
        return 1
    fi
    
    local url="$CODER_URL/api/v2$endpoint"
    local response
    local http_code
    
    if [[ -n "$data" ]]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Coder-Session-Token: $CODER_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Coder-Session-Token: $CODER_TOKEN" \
            "$url")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo "$body"
        return 0
    else
        log_error "API call failed with status $http_code"
        echo "$body" >&2
        return 1
    fi
}

# Get current user info
get_current_user() {
    coder_api_call GET "/users/me"
}

# Get organizations (typically just one: "default")
get_organizations() {
    coder_api_call GET "/organizations"
}

# Get default organization ID
get_default_org_id() {
    local orgs=$(get_organizations)
    echo "$orgs" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# List templates
list_templates() {
    local org_id=$(get_default_org_id)
    if [[ -z "$org_id" ]]; then
        log_error "Could not determine organization ID"
        return 1
    fi
    coder_api_call GET "/organizations/$org_id/templates"
}

# Check if template exists
template_exists() {
    local template_name="$1"
    local templates=$(list_templates)
    echo "$templates" | grep -q "\"name\":\"$template_name\""
}

# Test authentication
test_auth() {
    log_info "Testing Coder API authentication..."
    
    if ! check_token; then
        return 1
    fi
    
    local user_info=$(get_current_user 2>&1)
    if [[ $? -eq 0 ]]; then
        local username=$(echo "$user_info" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        local email=$(echo "$user_info" | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
        log_success "Authenticated as: $username ($email)"
        return 0
    else
        log_error "Authentication failed"
        log_info "Please verify your CODER_SESSION_TOKEN in .env"
        return 1
    fi
}

# Prompt user to setup Coder and get token
prompt_for_coder_setup() {
    local env_file="$WORKSPACE_ROOT/.env"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                   Coder Setup Required                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Coder is running at: $CODER_URL"
    echo ""
    echo "To generate your authentication token:"
    echo ""
    echo "  1. Open this URL in your browser:"
    echo "     $CODER_URL/cli-auth"
    echo ""
    echo "  2. If not logged in, create your admin account"
    echo "     (first user becomes admin)"
    echo ""
    echo "  3. The page will display your session token"
    echo "     Copy the entire token string"
    echo ""
    
    # Prompt for token
    local token=""
    while [[ -z "$token" ]]; do
        read -p "Paste your Coder session token: " -r token
        if [[ -z "$token" ]]; then
            log_warn "Token cannot be empty"
        fi
    done
    
    # Save to .env
    if grep -q "^CODER_SESSION_TOKEN=" "$env_file" 2>/dev/null; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^CODER_SESSION_TOKEN=.*|CODER_SESSION_TOKEN=$token|" "$env_file"
        else
            sed -i "s|^CODER_SESSION_TOKEN=.*|CODER_SESSION_TOKEN=$token|" "$env_file"
        fi
    else
        # Append new line
        echo "CODER_SESSION_TOKEN=$token" >> "$env_file"
    fi
    
    # Reload .env
    export CODER_SESSION_TOKEN="$token"
    CODER_TOKEN="$token"
    
    log_success "Token saved to .env"
    echo ""
    
    # Test authentication
    if test_auth; then
        log_success "Coder authentication successful!"
        echo ""
        return 0
    else
        log_error "Authentication test failed"
        log_info "Please verify the token is correct and try again"
        return 1
    fi
}

# Main - can be sourced or run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Run directly - test authentication
    case "${1:-test}" in
        test)
            test_auth
            ;;
        setup)
            prompt_for_coder_setup
            ;;
        user)
            get_current_user | jq '.' 2>/dev/null || get_current_user
            ;;
        org)
            get_organizations | jq '.' 2>/dev/null || get_organizations
            ;;
        templates)
            list_templates | jq '.' 2>/dev/null || list_templates
            ;;
        *)
            echo "Usage: $0 {test|setup|user|org|templates}"
            exit 1
            ;;
    esac
fi
