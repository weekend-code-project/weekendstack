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
        # Fallback: extract account ID from zone info (works when token has
        # zone-level permissions but not account-list permissions)
        log_info "Trying to get account ID from zone info..."
        local zone_response
        zone_response=$(cf_api_call GET "/zones?per_page=1")
        if [[ $? -eq 0 ]]; then
            account_id=$(echo "$zone_response" | jq -r '.result[0].account.id // empty')
        fi
    fi

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

# Infer the base domain from an existing tunnel's ingress configuration.
# Queries /accounts/{id}/cfd_tunnel/{tunnel_id}/configurations and extracts
# the first non-catch-all hostname, stripping any leading "*.".
# Returns 0 and echoes the domain on success, 1 if it cannot be determined.
cf_infer_domain_from_tunnel() {
    local account_id="$1"
    local tunnel_id="$2"

    local response
    response=$(cf_api_call GET "/accounts/$account_id/cfd_tunnel/$tunnel_id/configurations" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Extract all hostnames from ingress rules, skip the catch-all (empty hostname)
    local hostname
    hostname=$(echo "$response" | jq -r '
        .result.config.ingress[]?
        | select(.hostname != null and .hostname != "")
        | .hostname' 2>/dev/null | head -1)

    if [[ -z "$hostname" ]]; then
        return 1
    fi

    # Strip leading "*." wildcard to get the bare domain
    local domain="${hostname#\*.}"

    # Strip any leading subdomain that looks like a service name (e.g. traefik.example.com → example.com)
    # We want the registrable domain: last two labels. Only strip if there are 3+ labels.
    local label_count
    label_count=$(echo "$domain" | tr -cd '.' | wc -c)
    if [[ "$label_count" -ge 2 ]]; then
        domain=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
    fi

    if [[ -z "$domain" ]]; then
        return 1
    fi

    echo "$domain"
    return 0
}

# List all tunnels and let user pick one or create new
# Returns: tunnel_id|tunnel_name  or empty on "create new"
cf_pick_existing_tunnel() {
    local account_id="$1"
    local default_name="$2"
    
    local tunnels_json
    tunnels_json=$(cf_list_tunnels "$account_id")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Get non-deleted tunnels
    local tunnel_list
    tunnel_list=$(echo "$tunnels_json" | jq -r '.result[] | select(.deleted_at == null) | "\(.id)|\(.name)"' 2>/dev/null)
    
    if [[ -z "$tunnel_list" ]]; then
        log_info "No existing tunnels found in this account"
        return 1
    fi
    
    local count
    count=$(echo "$tunnel_list" | wc -l)
    
    echo "" >&2
    log_info "Found $count existing tunnel(s) in your account:"
    echo "" >&2

    local i=1
    local ids=() names=()
    while IFS='|' read -r tid tname; do
        echo "  $i. $tname (ID: ${tid:0:8}...)" >&2
        ids+=("$tid")
        names+=("$tname")
        i=$((i + 1))
    done <<< "$tunnel_list"
    echo "" >&2

    local choice
    echo -n "Select tunnel [1]: " >&2
    read -r choice </dev/tty
    choice=${choice:-1}

    if [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]] 2>/dev/null; then
        local idx=$((choice - 1))
        echo "${ids[$idx]}|${names[$idx]}"
        return 0
    fi

    log_warn "Invalid selection."
    return 1
}

# Delete old/unused tunnels to avoid token sprawl
cf_cleanup_old_tunnels() {
    local account_id="$1"
    local keep_tunnel_id="$2"  # Don't delete this one
    
    local tunnels_json
    tunnels_json=$(cf_list_tunnels "$account_id")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Get non-deleted tunnels excluding the one to keep
    local old_tunnels
    old_tunnels=$(echo "$tunnels_json" | jq -r ".result[] | select(.deleted_at == null) | select(.id != \"$keep_tunnel_id\") | \"\(.id)|\(.name)\"" 2>/dev/null)
    
    if [[ -z "$old_tunnels" ]]; then
        return 0
    fi
    
    local count
    count=$(echo "$old_tunnels" | wc -l)
    
    echo "" >&2
    log_warn "Found $count other tunnel(s) that may be unused:"
    while IFS='|' read -r tid tname; do
        echo "    • $tname (${tid:0:8}...)" >&2
    done <<< "$old_tunnels"
    echo "" >&2
    echo "  Old tunnels create stale API tokens in your Cloudflare account." >&2
    echo "" >&2
    
    if prompt_yes_no "Delete unused tunnels?" "y"; then
        while IFS='|' read -r tid tname; do
            # Must clean connections first
            cf_api_call DELETE "/accounts/$account_id/cfd_tunnel/$tid/connections" >/dev/null 2>&1
            if cf_delete_tunnel "$account_id" "$tid" >/dev/null 2>&1; then
                log_success "Deleted tunnel: $tname"
            else
                log_warn "Could not delete tunnel: $tname (may have active connections)"
            fi
        done <<< "$old_tunnels"
    fi
}

# Full automated setup workflow
cf_setup_tunnel_automated() {
    local tunnel_name="$1"
    local domain="$2"
    local stack_dir="${SCRIPT_DIR}"
    
    if [[ -z "$tunnel_name" ]]; then
        log_error "Tunnel name required"
        return 1
    fi
    # domain may be empty — it will be inferred from the tunnel's ingress config
    
    # Validate API token and get account ID
    local account_id
    account_id=$(cf_validate_token)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check for existing tunnels — offer to reuse before creating new
    local tunnel_id
    local picked
    picked=$(cf_pick_existing_tunnel "$account_id" "$tunnel_name")
    
    if [[ $? -eq 0 && -n "$picked" ]]; then
        tunnel_id=$(echo "$picked" | cut -d'|' -f1)
        tunnel_name=$(echo "$picked" | cut -d'|' -f2)
        log_success "Using tunnel: $tunnel_name (ID: $tunnel_id)"

        # Infer domain from tunnel ingress if not already known
        if [[ -z "$domain" || "$domain" == "localhost" ]]; then
            local inferred_domain
            inferred_domain=$(cf_infer_domain_from_tunnel "$account_id" "$tunnel_id" 2>/dev/null)
            if [[ -n "$inferred_domain" ]]; then
                log_info "Detected domain from tunnel config: $inferred_domain"
                domain="$inferred_domain"
            fi
        fi
    else
        log_error "No tunnel selected. Create a tunnel first at https://one.dash.cloudflare.com/ (Networks → Tunnels)."
        return 1
    fi
    
    # Export account ID so update_env_cloudflare can fetch the tunnel token
    export CLOUDFLARE_ACCOUNT_ID="$account_id"
    
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
    
    # Offer to clean up old tunnels to prevent API token sprawl
    cf_cleanup_old_tunnels "$account_id" "$tunnel_id"
    
    # Output tunnel info (include tunnel_name since user may have picked a different one,
    # and domain since it may have been inferred from the tunnel config)
    echo "$tunnel_id|$account_id|$tunnel_name|$domain"
    return 0
}

# Export functions
export -f cf_api_call cf_get_account_id cf_get_zone_id
export -f cf_list_tunnels cf_get_tunnel cf_create_tunnel
export -f cf_get_tunnel_token cf_delete_tunnel
export -f cf_create_dns_record cf_check_dns_record
export -f cf_validate_token cf_save_tunnel_credentials
export -f cf_infer_domain_from_tunnel
export -f cf_pick_existing_tunnel cf_cleanup_old_tunnels
export -f cf_setup_tunnel_automated
