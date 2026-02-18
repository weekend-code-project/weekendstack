#!/bin/bash
# Cloudflare Tunnel setup wizard
# Guides users through creating and configuring Cloudflare Tunnel

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

check_cloudflare_config() {
    local stack_dir="${SCRIPT_DIR}"
    local env_file="$stack_dir/.env"

    # Token-based setup: just need CLOUDFLARE_TUNNEL_TOKEN in .env
    if [[ -f "$env_file" ]]; then
        local token
        token=$(grep "^CLOUDFLARE_TUNNEL_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
        if [[ -n "$token" ]]; then
            return 0
        fi
    fi

    return 1
}

show_cloudflare_intro() {
    log_header "Cloudflare Tunnel Setup"
    
    echo "Cloudflare Tunnel provides secure access to your services from the internet"
    echo "without port forwarding or exposing your home IP address."
    echo ""
    echo "Requirements:"
    echo "  • Cloudflare account (free tier is fine)"
    echo "  • Domain name added to Cloudflare"
    echo ""
    
    # Prompt for domain at the beginning
    local stack_dir="${SCRIPT_DIR}"
    local current_domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    
    echo "Enter the domain name you want to use for external access."
    echo "This domain must be added to your Cloudflare account."
    echo ""
    
    local domain
    if [[ -n "$current_domain" ]] && [[ "$current_domain" != "localhost" ]]; then
        domain=$(prompt_input "Domain name" "$current_domain")
    else
        domain=$(prompt_input "Domain name (e.g., example.com or mystack.example.com)" "")
    fi
    
    if [[ -z "$domain" ]]; then
        log_error "Domain name is required for Cloudflare Tunnel"
        return 1
    fi
    
    # Update BASE_DOMAIN in .env
    if [[ -f "$stack_dir/.env" ]]; then
        sed -i "s|^BASE_DOMAIN=.*|BASE_DOMAIN=$domain|" "$stack_dir/.env"
        export CLOUDFLARE_DOMAIN="$domain"
    fi
    
    echo ""
    echo "Setup Methods:"
    echo "  1. API (Recommended) - Fully automated, requires API token"
    echo "     Create token at: https://dash.cloudflare.com/profile/api-tokens"
    echo "     Required permissions: Account:Cloudflare Tunnel:Edit, Zone:DNS:Edit"
    echo "  2. CLI - Uses cloudflared command-line tool (if installed)"
    echo "  3. Manual - You create tunnel in dashboard, provide credentials"
    echo "  4. None - Setup later"
    echo ""
}

setup_cloudflare_tunnel() {
    if ! show_cloudflare_intro; then
        return 1
    fi
    
    if check_cloudflare_config; then
        log_info "Cloudflare Tunnel configuration already exists"
        if ! prompt_yes_no "Reconfigure Cloudflare Tunnel?" "n"; then
            return 0
        fi
    fi
    
    # Offer setup method selection
    echo ""
    echo "Choose setup method:"
    echo ""
    echo "  1. API (Recommended) - Automated tunnel creation via API"
    echo "     Requires: Cloudflare API token"
    echo "     Creates tunnel, credentials, and DNS automatically"
    echo ""
    echo "  2. CLI - Uses cloudflared command-line tool"
    echo "     Requires: cloudflared CLI installed locally"
    echo "     Semi-automated with local commands"
    echo ""
    echo "  3. Manual - You handle tunnel creation"
    echo "     Requires: Manual tunnel creation in dashboard"
    echo "     You provide tunnel ID and credentials"
    echo ""
    echo "  4. None - Setup later"
    echo "     Skip Cloudflare configuration for now"
    echo ""
    
    read -p "Select method [1-4] (default: 1): " -r method
    method=${method:-1}
    
    case $method in
        1) # API method
            setup_tunnel_with_api
            ;;
        2) # CLI method
            if check_command cloudflared; then
                setup_tunnel_with_cli
            else
                log_error "cloudflared CLI not found. Install it or use another method."
                return 1
            fi
            ;;
        3) # Manual method
            setup_tunnel_manual
            ;;
        4) # Skip
            log_info "Skipping Cloudflare Tunnel setup"
            log_info "You can configure it manually later - see docs/cloudflare-tunnel-setup.md"
            return 0
            ;;
        *)
            log_error "Invalid selection"
            return 1
            ;;
    esac
}

setup_tunnel_with_cli() {
    log_header "Cloudflare Tunnel Setup (CLI Method)"
    
    local stack_dir="${SCRIPT_DIR}"
    local tunnel_name
    local domain="${CLOUDFLARE_DOMAIN}"
    
    # Domain should already be set by show_cloudflare_intro
    if [[ -z "$domain" ]]; then
        domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        log_error "Domain name is required for Cloudflare Tunnel"
        return 1
    fi
    
    tunnel_name=$(prompt_input "Tunnel name" "weekendstack-tunnel")
    
    echo ""
    log_step "Authenticating with Cloudflare..."
    echo "This will open a browser window for authentication."
    echo ""
    
    if ! cloudflared tunnel login; then
        log_error "Failed to authenticate with Cloudflare"
        return 1
    fi
    
    log_success "Authenticated with Cloudflare"
    
    echo ""
    log_step "Creating tunnel: $tunnel_name"
    
    if ! cloudflared tunnel create "$tunnel_name"; then
        log_error "Failed to create tunnel"
        log_info "Tunnel may already exist. Listing tunnels:"
        cloudflared tunnel list
        return 1
    fi
    
    local tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')
    
    if [[ -z "$tunnel_id" ]]; then
        log_error "Could not determine tunnel ID"
        return 1
    fi
    
    log_success "Created tunnel: $tunnel_name (ID: $tunnel_id)"
    
    # Copy credentials file
    local creds_source="$HOME/.cloudflared/$tunnel_id.json"
    local creds_dest="$stack_dir/config/cloudflare/.cloudflared/$tunnel_id.json"
    
    mkdir -p "$stack_dir/config/cloudflare/.cloudflared"
    if [[ -f "$creds_source" ]]; then
        cp "$creds_source" "$creds_dest"
        chmod 600 "$creds_dest"
        log_success "Copied credentials to config/cloudflare/.cloudflared/"
    else
        log_error "Credentials file not found: $creds_source"
        return 1
    fi
    
    # Create config.yml
    create_tunnel_config "$tunnel_name" "$tunnel_id" "$domain"
    
    # Create DNS record
    echo ""
    log_step "Creating DNS record..."
    
    if cloudflared tunnel route dns "$tunnel_name" "*.$domain"; then
        log_success "Created wildcard DNS record: *.$domain"
    else
        log_warn "Failed to create DNS record automatically"
        log_info "You may need to create it manually in Cloudflare dashboard"
    fi
    
    # Update .env
    update_env_cloudflare "$tunnel_name" "$tunnel_id" "$domain"
    
    log_success "Cloudflare Tunnel setup complete!"
    display_tunnel_status "$tunnel_name"
}

setup_tunnel_with_api() {
    log_header "Cloudflare Tunnel Setup (API Method)"
    
    # Load API library
    local api_lib="$(dirname "${BASH_SOURCE[0]}")/cloudflare-api.sh"
    if [[ ! -f "$api_lib" ]]; then
        log_error "API library not found: $api_lib"
        return 1
    fi
    source "$api_lib"
    
    local stack_dir="${SCRIPT_DIR}"
    local tunnel_name
    local domain="${CLOUDFLARE_DOMAIN}"
    
    # Domain should already be set by show_cloudflare_intro
    if [[ -z "$domain" ]]; then
        domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        log_error "Domain name is required for Cloudflare Tunnel"
        return 1
    fi
    
    tunnel_name=$(prompt_input "Tunnel name" "weekendstack-tunnel")
    
    echo ""
    log_step "API Token Configuration"
    echo ""
    echo "You need a Cloudflare API token with these permissions:"
    echo "  • Account - Cloudflare Tunnel - Edit"
    echo "  • Zone - DNS - Edit (for zone: $domain)"
    echo ""
    echo "Create token at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    
    # Check if API token already in .env
    local api_token=""
    if [[ -f "$stack_dir/.env" ]]; then
        api_token=$(grep "^CLOUDFLARE_API_TOKEN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi
    
    if [[ -n "$api_token" ]]; then
        log_info "Found existing API token in .env"
        if ! prompt_yes_no "Use existing API token?" "y"; then
            api_token=""
        fi
    fi
    
    if [[ -z "$api_token" ]]; then
        api_token=$(prompt_input "Enter Cloudflare API token" "")
        
        if [[ -z "$api_token" ]]; then
            log_warn "API token required for automated setup"
            log_info "Falling back to manual method..."
            echo ""
            sleep 2
            setup_tunnel_manual
            return $?
        fi
    fi
    
    # Detect common mistake: entering Account ID (32-char hex) instead of API token
    if [[ "$api_token" =~ ^[0-9a-f]{32}$ ]]; then
        log_warn "This looks like a Cloudflare Account ID, not an API token."
        echo ""
        echo "  Account ID (32 hex chars):  $api_token"
        echo ""
        echo "  API tokens are ~40 chars and contain mixed case letters + numbers."
        echo "  Create one at: https://dash.cloudflare.com/profile/api-tokens"
        echo ""
        local corrected_token
        corrected_token=$(prompt_input "Enter the correct API token (or press Enter to skip)" "")
        if [[ -n "$corrected_token" ]]; then
            # Save the hex value as account ID since user likely has it
            if grep -q "^CLOUDFLARE_ACCOUNT_ID=" "$stack_dir/.env"; then
                sed -i "s|^CLOUDFLARE_ACCOUNT_ID=.*|CLOUDFLARE_ACCOUNT_ID=$api_token|" "$stack_dir/.env"
            else
                echo "CLOUDFLARE_ACCOUNT_ID=$api_token" >> "$stack_dir/.env"
            fi
            api_token="$corrected_token"
        else
            log_warn "API token required for automated setup"
            log_info "Falling back to manual method..."
            echo ""
            setup_tunnel_manual
            return $?
        fi
    fi
    
    # Validate the API token against Cloudflare before proceeding
    log_step "Validating API token..."
    local verify_response
    verify_response=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $api_token" 2>&1)
    
    local token_status
    token_status=$(echo "$verify_response" | jq -r '.result.status // empty' 2>/dev/null)
    
    if [[ "$token_status" != "active" ]]; then
        local error_msg
        error_msg=$(echo "$verify_response" | jq -r '.errors[0].message // "Unknown error"' 2>/dev/null)
        log_error "API token validation failed: $error_msg"
        echo ""
        echo "  Possible causes:"
        echo "    • Token was revoked or expired"
        echo "    • Account ID was entered instead of API token"
        echo "    • Token was copied incorrectly"
        echo ""
        echo "  Create a new token at: https://dash.cloudflare.com/profile/api-tokens"
        echo "  Required permissions: Account:Cloudflare Tunnel:Edit, Zone:DNS:Edit"
        echo ""
        
        if prompt_yes_no "Enter a different token?" "y"; then
            api_token=$(prompt_input "Enter Cloudflare API token" "")
            if [[ -z "$api_token" ]]; then
                log_info "Falling back to manual method..."
                setup_tunnel_manual
                return $?
            fi
            # Re-validate
            verify_response=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
                -H "Authorization: Bearer $api_token" 2>&1)
            token_status=$(echo "$verify_response" | jq -r '.result.status // empty' 2>/dev/null)
            if [[ "$token_status" != "active" ]]; then
                log_error "Token still invalid. Falling back to manual method."
                setup_tunnel_manual
                return $?
            fi
        else
            log_info "Falling back to manual method..."
            setup_tunnel_manual
            return $?
        fi
    fi
    log_success "API token is valid"
    
    # Save validated token to .env
    if grep -q "^CLOUDFLARE_API_TOKEN=" "$stack_dir/.env"; then
        sed -i "s|^CLOUDFLARE_API_TOKEN=.*|CLOUDFLARE_API_TOKEN=$api_token|" "$stack_dir/.env"
    else
        echo "CLOUDFLARE_API_TOKEN=$api_token" >> "$stack_dir/.env"
    fi
    
    # Export for API library
    export CLOUDFLARE_API_TOKEN="$api_token"
    
    echo ""
    log_header "Creating Cloudflare Tunnel via API"
    
    # Run automated setup
    local result
    result=$(cf_setup_tunnel_automated "$tunnel_name" "$domain")
    
    if [[ $? -ne 0 ]]; then
        log_error "Automated tunnel setup failed"
        log_info "You can try the manual method instead"
        return 1
    fi
    
    # Parse result (format: tunnel_id|account_id|tunnel_name)
    local tunnel_id=$(echo "$result" | cut -d'|' -f1)
    local account_id=$(echo "$result" | cut -d'|' -f2)
    local resolved_name=$(echo "$result" | cut -d'|' -f3)
    # User may have picked an existing tunnel with a different name
    if [[ -n "$resolved_name" ]]; then
        tunnel_name="$resolved_name"
    fi
    
    # Create config.yml
    create_tunnel_config "$tunnel_name" "$tunnel_id" "$domain"
    
    # Update .env with all Cloudflare settings
    update_env_cloudflare "$tunnel_name" "$tunnel_id" "$domain"
    
    # Save account ID
    if grep -q "^CLOUDFLARE_ACCOUNT_ID=" "$stack_dir/.env"; then
        sed -i "s/^CLOUDFLARE_ACCOUNT_ID=.*/CLOUDFLARE_ACCOUNT_ID=$account_id/" "$stack_dir/.env"
    else
        echo "CLOUDFLARE_ACCOUNT_ID=$account_id" >> "$stack_dir/.env"
    fi
    
    echo ""
    log_success "Cloudflare Tunnel setup complete via API!"
    echo ""
    log_info "Tunnel created: $tunnel_name"
    log_info "Tunnel ID: $tunnel_id"
    log_info "DNS configured: *.$domain → ${tunnel_id}.cfargotunnel.com"
    echo ""
    
    display_tunnel_status "$tunnel_name"
}

setup_tunnel_manual() {
    log_header "Cloudflare Tunnel Setup (Manual Method)"
    
    echo "Follow these steps to create a Cloudflare Tunnel:"
    echo ""
    echo "1. Go to Cloudflare Zero Trust Dashboard:"
    echo "   https://one.dash.cloudflare.com/"
    echo ""
    echo "2. Navigate to: Networks > Tunnels"
    echo ""
    echo "3. Click 'Create a tunnel'"
    echo ""
    echo "4. Choose 'Cloudflared' as connector"
    echo ""
    echo "5. Name your tunnel (e.g., 'weekendstack-tunnel')"
    echo ""
    echo "6. DO NOT install the connector - we'll use Docker"
    echo ""
    echo "7. Copy the tunnel credentials:"
    echo "   - Download the JSON credentials file, OR"
    echo "   - Copy the tunnel token"
    echo ""
    
    if ! prompt_yes_no "Have you created the tunnel in Cloudflare dashboard?" "n"; then
        log_info "Please create the tunnel first, then run setup again"
        return 1
    fi
    
    local stack_dir="${SCRIPT_DIR}"
    local tunnel_name
    local tunnel_id
    
    tunnel_name=$(prompt_input "Tunnel name (as shown in dashboard)" "weekendstack-tunnel")
    tunnel_id=$(prompt_input "Tunnel ID (UUID from dashboard)" "")
    
    if [[ -z "$tunnel_id" ]]; then
        log_error "Tunnel ID is required"
        return 1
    fi
    
    # Domain should already be set by show_cloudflare_intro
    local domain="${CLOUDFLARE_DOMAIN}"
    if [[ -z "$domain" ]]; then
        domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        log_error "Domain name is required for Cloudflare Tunnel"
        return 1
    fi
    
    # Get credentials
    echo ""
    echo "How do you want to provide credentials?"
    echo ""
    echo "  1. Tunnel token       - Copy from Cloudflare dashboard (recommended)"
    echo "  2. JSON file path     - Provide path to downloaded credentials file"
    echo "  3. Paste JSON content - Copy/paste the JSON directly"
    echo ""
    local creds_method
    creds_method=$(prompt_select "Select [1-3]:" "Tunnel token" "JSON file path" "Paste JSON content")
    
    case $creds_method in
        0) # Tunnel token
            echo ""
            echo "In the Cloudflare dashboard, go to:"
            echo "  Networks > Tunnels > $tunnel_name > Overview > Install connector"
            echo "Copy the token from the connector install command."
            echo ""
            local tunnel_token
            tunnel_token=$(prompt_input "Tunnel token" "")
            
            if [[ -z "$tunnel_token" ]]; then
                log_error "Tunnel token is required"
                return 1
            fi
            
            # Save token directly to .env
            local env_file="$stack_dir/.env"
            if grep -q "^CLOUDFLARE_TUNNEL_TOKEN=" "$env_file" 2>/dev/null; then
                sed -i "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token|" "$env_file"
            else
                echo "CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token" >> "$env_file"
            fi
            log_success "Saved tunnel token to .env"
            ;;
            
        1) # File path
            local creds_file
            creds_file=$(prompt_input "Path to credentials JSON file" "")
            
            if [[ ! -f "$creds_file" ]]; then
                log_error "File not found: $creds_file"
                return 1
            fi
            
            mkdir -p "$stack_dir/config/cloudflare/.cloudflared"
            cp "$creds_file" "$stack_dir/config/cloudflare/.cloudflared/$tunnel_id.json"
            chmod 600 "$stack_dir/config/cloudflare/.cloudflared/$tunnel_id.json"
            log_success "Copied credentials file"
            ;;
            
        2) # Paste JSON
            mkdir -p "$stack_dir/config/cloudflare/.cloudflared"
            log_info "Paste the JSON credentials (press Ctrl+D when done):"
            cat > "$stack_dir/config/cloudflare/.cloudflared/$tunnel_id.json"
            chmod 600 "$stack_dir/config/cloudflare/.cloudflared/$tunnel_id.json"
            log_success "Saved credentials file"
            ;;
    esac
    
    # Create config.yml
    create_tunnel_config "$tunnel_name" "$tunnel_id" "$domain"
    
    # Manual DNS instructions
    echo ""
    log_warn "DNS Record Required"
    echo "Create a CNAME record in Cloudflare DNS:"
    echo ""
    echo "  Type:    CNAME"
    echo "  Name:    *.$domain  (or just *)"
    echo "  Target:  $tunnel_id.cfargotunnel.com"
    echo "  Proxied: Yes (orange cloud)"
    echo ""
    
    prompt_yes_no "Press Enter when DNS record is created" "y" >/dev/null
    
    # Update .env
    update_env_cloudflare "$tunnel_name" "$tunnel_id" "$domain"
    
    log_success "Cloudflare Tunnel configuration complete!"
    display_tunnel_status "$tunnel_name"
}

create_tunnel_config() {
    local tunnel_name="$1"
    local tunnel_id="$2"
    local domain="$3"
    local stack_dir="${SCRIPT_DIR}"
    
    log_step "Configuring tunnel ingress rules via Cloudflare API..."
    
    local account_id="${CLOUDFLARE_ACCOUNT_ID}"
    if [[ -z "$account_id" ]]; then
        account_id=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi
    
    if [[ -z "$account_id" ]]; then
        log_warn "Account ID not available, skipping remote ingress config"
        log_info "Configure ingress rules in the Cloudflare dashboard:"
        log_info "  https://one.dash.cloudflare.com/ → Tunnels → $tunnel_name → Public Hostname"
        return 0
    fi
    
    # Set ingress rules via API (remote config)
    local ingress_config
    ingress_config=$(cat <<JSONEOF
{
  "config": {
    "ingress": [
      {
        "hostname": "*.$domain",
        "service": "https://traefik:443",
        "originRequest": {
          "noTLSVerify": true
        }
      },
      {
        "service": "http_status:404"
      }
    ]
  }
}
JSONEOF
)
    
    local response
    response=$(cf_api_call PUT "/accounts/$account_id/cfd_tunnel/$tunnel_id/configurations" "$ingress_config")
    
    if [[ $? -eq 0 ]]; then
        log_success "Ingress rules configured via Cloudflare API"
    else
        log_warn "Failed to set ingress rules via API"
        log_info "Configure manually in Cloudflare dashboard:"
        log_info "  Public hostname: *.$domain → https://traefik:443 (noTLSVerify)"
    fi
}

update_env_cloudflare() {
    local tunnel_name="$1"
    local tunnel_id="$2"
    local domain="$3"
    local stack_dir="${SCRIPT_DIR}"
    local env_file="$stack_dir/.env"
    
    if [[ ! -f "$env_file" ]]; then
        return 0
    fi
    
    # Check if Cloudflare section exists
    if ! grep -q "CLOUDFLARE_TUNNEL_ENABLED" "$env_file"; then
        cat >> "$env_file" << EOF

# =============================================================================
# Cloudflare Tunnel Configuration
# =============================================================================
CLOUDFLARE_TUNNEL_ENABLED=true
CLOUDFLARE_TUNNEL_NAME=$tunnel_name
CLOUDFLARE_TUNNEL_ID=$tunnel_id
EOF
    else
        sed -i "s/^CLOUDFLARE_TUNNEL_ENABLED=.*/CLOUDFLARE_TUNNEL_ENABLED=true/" "$env_file"
        sed -i "s/^CLOUDFLARE_TUNNEL_NAME=.*/CLOUDFLARE_TUNNEL_NAME=$tunnel_name/" "$env_file"
        sed -i "s/^CLOUDFLARE_TUNNEL_ID=.*/CLOUDFLARE_TUNNEL_ID=$tunnel_id/" "$env_file"
    fi
    
    # Ensure BASE_DOMAIN is set
    sed -i "s/^BASE_DOMAIN=.*/BASE_DOMAIN=$domain/" "$env_file"
    
    # Save tunnel token for token-based run
    local account_id="${CLOUDFLARE_ACCOUNT_ID}"
    if [[ -z "$account_id" ]]; then
        account_id=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "$env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi
    
    if [[ -n "$account_id" ]]; then
        local tunnel_token
        tunnel_token=$(cf_get_tunnel_token "$account_id" "$tunnel_id")
        if [[ $? -eq 0 && -n "$tunnel_token" ]]; then
            if grep -q "^CLOUDFLARE_TUNNEL_TOKEN=" "$env_file"; then
                sed -i "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token|" "$env_file"
            else
                echo "CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token" >> "$env_file"
            fi
            log_success "Saved tunnel token to .env"
        else
            log_warn "Could not retrieve tunnel token"
        fi
    fi
}

display_tunnel_status() {
    local tunnel_name="$1"
    local stack_dir="${SCRIPT_DIR}"
    local domain
    domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    
    echo ""
    echo "${BOLD}Cloudflare Tunnel Setup Complete!${NC}"
    echo ""
    echo "Remote Access (via Cloudflare — TLS handled automatically):"
    echo "  https://<service>.$domain → Cloudflare → Tunnel → Traefik → Service"
    echo "  No certificates to install on client devices for remote access."
    echo ""
    echo "Local LAN Access (via Pi-hole DNS + self-signed certs):"
    local lab_domain
    lab_domain=$(grep "^LAB_DOMAIN=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    lab_domain=${lab_domain:-lab}
    echo "  https://<service>.$lab_domain → Traefik → Service"
    echo "  CA cert for LAN devices: config/traefik/certs/ca-cert.pem"
    echo ""
    echo "${BOLD}Next Steps:${NC}"
    echo "1. Start the stack:   ./setup.sh --start"
    echo "2. Check tunnel logs: docker logs cloudflare-tunnel"
    echo "3. Test remote:       https://home.$domain"
    echo ""
}

test_tunnel_connectivity() {
    local stack_dir="${SCRIPT_DIR}"
    
    if [[ ! -f "$stack_dir/.env" ]]; then
        log_error "No .env file found"
        return 1
    fi
    
    local domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        log_warn "No external domain configured"
        return 1
    fi
    
    log_step "Testing Cloudflare Tunnel connectivity..."
    
    # Check if tunnel container is running
    if ! docker ps --format '{{.Names}}' | grep -q "cloudflare-tunnel"; then
        log_warn "Cloudflare tunnel container not running"
        return 1
    fi
    
    # Test DNS resolution
    if host "*.$domain" >/dev/null 2>&1; then
        log_success "DNS resolution working"
    else
        log_warn "DNS resolution failed for *.$domain"
    fi
    
    log_info "Tunnel appears to be configured. Test by accessing:"
    log_info "  https://home.$domain (Glance dashboard)"
}

# Export functions
export -f check_cloudflare_config show_cloudflare_intro setup_cloudflare_tunnel
export -f setup_tunnel_with_cli setup_tunnel_with_api setup_tunnel_manual create_tunnel_config
export -f update_env_cloudflare display_tunnel_status test_tunnel_connectivity
