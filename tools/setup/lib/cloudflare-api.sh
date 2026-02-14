#!/bin/bash
# Cloudflare API client library
# Provides functions for automated tunnel creation and management via Cloudflare API

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# API endpoint
CF_API_BASE="https://api.cloudflare.com/client/v4"

# Generic Cloudflare API call function
# Usage: cf_api_call METHOD ENDPOINT [DATA]
cf_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local api_token="${CLOUDFLARE_API_TOKEN}"
    
    if [[ -z "$api_token" ]]; then
        log_error "CLOUDFLARE_API_TOKEN not set"
        return 1
    fi
    
    local url="${CF_API_BASE}${endpoint}"
    local response
    local http_code
    
    if [[ -n "$data" ]]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Authorization: Bearer $api_token" \
            -H "Content-Type: application/json" \
            -d "$data" 2>&1)
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" \
            -H "Authorization: Bearer $api_token" \
            -H "Content-Type: application/json" 2>&1)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    # Check for success (2xx status codes)
    if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
        echo "$body"
        return 0
    else
        log_error "API call failed with HTTP $http_code"
        echo "$body" | jq -r '.errors[]? | .message' 2>/dev/null || echo "$body" >&2
        return 1
    fi
}

# Get Cloudflare account ID from API token
cf_get_account_id() {
    log_step "Retrieving Cloudflare account ID..."
    
    local response
    response=$(cf_api_call GET "/accounts")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve account information"
        return 1
    fi
    
    local account_id=$(echo "$response" | jq -r '.result[0].id // empty')
    
    if [[ -z "$account_id" ]]; then
        log_error "No account found for this API token"
        return 1
    fi
    
    echo "$account_id"
    return 0
}

# Get zone ID from domain name
cf_get_zone_id() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        log_error "Domain name required"
        return 1
    fi
    
    log_step "Looking up zone ID for $domain..."
    
    local response
    response=$(cf_api_call GET "/zones?name=$domain")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve zone information"
        return 1
    fi
    
    local zone_id=$(echo "$response" | jq -r '.result[0].id // empty')
    
    if [[ -z "$zone_id" ]]; then
        log_error "Zone not found for domain: $domain"
        log_info "Ensure $domain is added to your Cloudflare account"
        return 1
    fi
    
    echo "$zone_id"
    return 0
}

# List all tunnels for account
cf_list_tunnels() {
    local account_id="$1"
    
    if [[ -z "$account_id" ]]; then
        log_error "Account ID required"
        return 1
    fi
    
    log_step "Listing existing tunnels..."
    
    local response
    response=$(cf_api_call GET "/accounts/$account_id/cfd_tunnel")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$response"
    return 0
}

# Get specific tunnel by name
cf_get_tunnel() {
    local account_id="$1"
    local tunnel_name="$2"
    
    if [[ -z "$account_id" ]] || [[ -z "$tunnel_name" ]]; then
        log_error "Account ID and tunnel name required"
        return 1
    fi
    
    local tunnels
    tunnels=$(cf_list_tunnels "$account_id")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local tunnel_id=$(echo "$tunnels" | jq -r ".result[] | select(.name == \"$tunnel_name\") | .id // empty")
    
    if [[ -n "$tunnel_id" ]]; then
        echo "$tunnel_id"
        return 0
    else
        return 1
    fi
}

# Create a new tunnel
cf_create_tunnel() {
    local account_id="$1"
    local tunnel_name="$2"
    local tunnel_secret="${3:-$(openssl rand -hex 32)}"
    
    if [[ -z "$account_id" ]] || [[ -z "$tunnel_name" ]]; then
        log_error "Account ID and tunnel name required"
        return 1
    fi
    
    log_step "Creating tunnel: $tunnel_name..."
    
    local data=$(jq -n \
        --arg name "$tunnel_name" \
        --arg secret "$tunnel_secret" \
        '{name: $name, tunnel_secret: $secret}')
    
    local response
    response=$(cf_api_call POST "/accounts/$account_id/cfd_tunnel" "$data")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create tunnel"
        return 1
    fi
    
    echo "$response"
    return 0
}

# Get tunnel token for existing tunnel
cf_get_tunnel_token() {
    local account_id="$1"
    local tunnel_id="$2"
    
    if [[ -z "$account_id" ]] || [[ -z "$tunnel_id" ]]; then
        log_error "Account ID and tunnel ID required"
        return 1
    fi
    
    log_step "Retrieving tunnel token..."
    
    local response
    response=$(cf_api_call GET "/accounts/$account_id/cfd_tunnel/$tunnel_id/token")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to retrieve tunnel token"
        return 1
    fi
    
    local token=$(echo "$response" | jq -r '.result // empty')
    
    if [[ -z "$token" ]]; then
        log_error "Tunnel token not found in response"
        return 1
    fi
    
    echo "$token"
    return 0
}

# Delete a tunnel
cf_delete_tunnel() {
    local account_id="$1"
    local tunnel_id="$2"
    
    if [[ -z "$account_id" ]] || [[ -z "$tunnel_id" ]]; then
        log_error "Account ID and tunnel ID required"
        return 1
    fi
    
    log_step "Deleting tunnel $tunnel_id..."
    
    cf_api_call DELETE "/accounts/$account_id/cfd_tunnel/$tunnel_id"
    return $?
}

# Create DNS record for tunnel
cf_create_dns_record() {
    local zone_id="$1"
    local name="$2"
    local tunnel_id="$3"
    local proxied="${4:-true}"
    
    if [[ -z "$zone_id" ]] || [[ -z "$name" ]] || [[ -z "$tunnel_id" ]]; then
        log_error "Zone ID, name, and tunnel ID required"
        return 1
    fi
    
    log_step "Creating DNS record: $name..."
    
    local target="${tunnel_id}.cfargotunnel.com"
    local data=$(jq -n \
        --arg type "CNAME" \
        --arg name "$name" \
        --arg content "$target" \
        --argjson proxied "$proxied" \
        '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: 1}')
    
    local response
    response=$(cf_api_call POST "/zones/$zone_id/dns_records" "$data")
    
    if [[ $? -ne 0 ]]; then
        # Check if record already exists
        if echo "$response" | grep -q "already exists"; then
            log_warn "DNS record already exists for $name"
            return 0
        fi
        log_error "Failed to create DNS record"
        return 1
    fi
    
    log_success "Created DNS record: $name → $target"
    return 0
}

# Check if DNS record exists
cf_check_dns_record() {
    local zone_id="$1"
    local name="$2"
    
    if [[ -z "$zone_id" ]] || [[ -z "$name" ]]; then
        log_error "Zone ID and name required"
        return 1
    fi
    
    local response
    response=$(cf_api_call GET "/zones/$zone_id/dns_records?name=$name&type=CNAME")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local count=$(echo "$response" | jq -r '.result | length')
    
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Validate API token has required permissions
cf_validate_token() {
    log_step "Validating Cloudflare API token..."
    
    # Try to get account info
    local account_id
    account_id=$(cf_get_account_id)
    
    if [[ $? -ne 0 ]]; then
        log_error "API token is invalid or lacks required permissions"
        log_info "Required permissions: Account.Cloudflare Tunnel:Edit, Zone.DNS:Edit"
        log_info "Create token at: https://dash.cloudflare.com/profile/api-tokens"
        return 1
    fi
    
    log_success "API token validated (Account ID: $account_id)"
    echo "$account_id"
    return 0
}

# Generate credentials JSON file from tunnel response
cf_save_tunnel_credentials() {
    local tunnel_response="$1"
    local output_file="$2"
    
    if [[ -z "$tunnel_response" ]] || [[ -z "$output_file" ]]; then
        log_error "Tunnel response and output file required"
        return 1
    fi
    
    local tunnel_id=$(echo "$tunnel_response" | jq -r '.result.id')
    local account_tag=$(echo "$tunnel_response" | jq -r '.result.account_tag')
    local tunnel_secret=$(echo "$tunnel_response" | jq -r '.result.tunnel_secret')
    local tunnel_name=$(echo "$tunnel_response" | jq -r '.result.name')
    
    if [[ -z "$tunnel_id" ]] || [[ -z "$account_tag" ]] || [[ -z "$tunnel_secret" ]]; then
        log_error "Missing required fields in tunnel response"
        return 1
    fi
    
    # Create credentials JSON in the format cloudflared expects
    local credentials=$(jq -n \
        --arg account_tag "$account_tag" \
        --arg tunnel_id "$tunnel_id" \
        --arg tunnel_secret "$tunnel_secret" \
        '{AccountTag: $account_tag, TunnelID: $tunnel_id, TunnelSecret: $tunnel_secret}')
    
    echo "$credentials" > "$output_file"
    chmod 600 "$output_file"
    
    log_success "Saved credentials to: $output_file"
    echo "$tunnel_id"
    return 0
}

# Full automated setup workflow
cf_setup_tunnel_automated() {
    local tunnel_name="$1"
    local domain="$2"
    local stack_dir="${SCRIPT_DIR}"
    
    if [[ -z "$tunnel_name" ]] || [[ -z "$domain" ]]; then
        log_error "Tunnel name and domain required"
        return 1
    fi
    
    # Validate API token and get account ID
    local account_id
    account_id=$(cf_validate_token)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if tunnel already exists
    local tunnel_id
    tunnel_id=$(cf_get_tunnel "$account_id" "$tunnel_name")
    local tunnel_exists=$?
    
    if [[ $tunnel_exists -eq 0 ]]; then
        log_info "Tunnel '$tunnel_name' already exists (ID: $tunnel_id)"
        
        if ! prompt_yes_no "Use existing tunnel?" "y"; then
            log_info "Please choose a different tunnel name or delete the existing tunnel"
            return 1
        fi
    else
        # Create new tunnel
        log_header "Creating Cloudflare Tunnel"
        
        local tunnel_response
        tunnel_response=$(cf_create_tunnel "$account_id" "$tunnel_name")
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create tunnel"
            return 1
        fi
        
        # Save credentials
        mkdir -p "$stack_dir/config/cloudflare"
        local temp_tunnel_id=$(echo "$tunnel_response" | jq -r '.result.id')
        local creds_file="$stack_dir/config/cloudflare/${temp_tunnel_id}.json"
        
        tunnel_id=$(cf_save_tunnel_credentials "$tunnel_response" "$creds_file")
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to save credentials"
            return 1
        fi
        
        log_success "Created tunnel: $tunnel_name (ID: $tunnel_id)"
    fi
    
    # Get zone ID for domain
    local zone_id
    zone_id=$(cf_get_zone_id "$domain")
    
    if [[ $? -ne 0 ]]; then
        log_warn "Could not find zone for domain: $domain"
        log_info "Skipping DNS record creation"
        log_info "Manually create CNAME: * → ${tunnel_id}.cfargotunnel.com"
    else
        # Create wildcard DNS record
        cf_create_dns_record "$zone_id" "*" "$tunnel_id" true
        
        if [[ $? -eq 0 ]]; then
            log_success "DNS configuration complete"
        else
            log_warn "DNS record creation failed"
            log_info "Manually create CNAME: * → ${tunnel_id}.cfargotunnel.com"
        fi
    fi
    
    # Output tunnel info
    echo "$tunnel_id|$account_id"
    return 0
}

# Export functions
export -f cf_api_call cf_get_account_id cf_get_zone_id
export -f cf_list_tunnels cf_get_tunnel cf_create_tunnel
export -f cf_get_tunnel_token cf_delete_tunnel
export -f cf_create_dns_record cf_check_dns_record
export -f cf_validate_token cf_save_tunnel_credentials
export -f cf_setup_tunnel_automated
