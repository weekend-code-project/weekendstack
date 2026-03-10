#!/bin/bash
# Cloudflare Tunnel setup wizard
# Guides users through creating and configuring Cloudflare Tunnel

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Verify API token against Cloudflare.
# Tries the User Token endpoint first, then falls back to the Account Token
# endpoint (Account API Tokens only validate on the account-scoped path).
# Returns 0 if active, 1 otherwise.
_cf_verify_token() {
    local token="$1"
    local status

    # 1) Try User API Token endpoint
    status=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $token" 2>/dev/null \
        | jq -r '.result.status // empty' 2>/dev/null)
    if [[ "$status" == "active" ]]; then
        return 0
    fi

    # 2) Fall back to Account API Token endpoint (needs account ID)
    #    Get account ID from .env or by querying the /accounts endpoint
    local account_id=""
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        account_id=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "${SCRIPT_DIR}/.env" 2>/dev/null \
            | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    fi

    if [[ -z "$account_id" ]]; then
        # Try to discover account ID via the token itself
        account_id=$(curl -s "https://api.cloudflare.com/client/v4/accounts" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" 2>/dev/null \
            | jq -r '.result[0].id // empty' 2>/dev/null)
    fi

    if [[ -n "$account_id" ]]; then
        status=$(curl -s "https://api.cloudflare.com/client/v4/accounts/$account_id/tokens/verify" \
            -H "Authorization: Bearer $token" 2>/dev/null \
            | jq -r '.result.status // empty' 2>/dev/null)
        if [[ "$status" == "active" ]]; then
            # Persist account ID so later steps don't need to re-discover it
            if [[ -f "${SCRIPT_DIR}/.env" ]]; then
                if grep -q "^CLOUDFLARE_ACCOUNT_ID=" "${SCRIPT_DIR}/.env"; then
                    sed -i "s|^CLOUDFLARE_ACCOUNT_ID=.*|CLOUDFLARE_ACCOUNT_ID=$account_id|" "${SCRIPT_DIR}/.env"
                else
                    echo "CLOUDFLARE_ACCOUNT_ID=$account_id" >> "${SCRIPT_DIR}/.env"
                fi
            fi
            return 0
        fi
    fi

    return 1
}

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
    echo "  • API token: Account:Cloudflare Tunnel:Edit + Zone:DNS:Edit"
    echo "    Create at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
}

setup_cloudflare_tunnel() {
    show_cloudflare_intro

    # ── Fast-path: API token + tunnel ID are set but connector token is missing ──
    # No need for the full wizard — just fetch the token from the API.
    local _env_file="${SCRIPT_DIR}/.env"
    local _api_token _tunnel_id _existing_token
    _api_token=$(grep "^CLOUDFLARE_API_TOKEN="  "$_env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    _tunnel_id=$(grep "^CLOUDFLARE_TUNNEL_ID="  "$_env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    _existing_token=$(grep "^CLOUDFLARE_TUNNEL_TOKEN=" "$_env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')

    if [[ -n "$_api_token" && -n "$_tunnel_id" && -z "$_existing_token" ]]; then
        log_step "API token and tunnel ID found — fetching connector token automatically..."
        local _account_id
        _account_id=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "$_env_file" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
        if [[ -z "$_account_id" ]]; then
            _account_id=$(curl -s "https://api.cloudflare.com/client/v4/accounts" \
                -H "Authorization: Bearer $_api_token" | jq -r '.result[0].id // empty' 2>/dev/null)
        fi
        if [[ -n "$_account_id" ]]; then
            local _connector_token
            _connector_token=$(curl -s \
                "https://api.cloudflare.com/client/v4/accounts/$_account_id/cfd_tunnel/$_tunnel_id/token" \
                -H "Authorization: Bearer $_api_token" | jq -r '.result // empty' 2>/dev/null)
            if [[ -n "$_connector_token" ]]; then
                sed -i "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=$_connector_token|" "$_env_file"
                log_success "Connector token fetched and saved automatically"
                export CLOUDFLARE_TUNNEL_ENABLED=true
                return 0
            else
                log_warn "Could not fetch connector token — continuing with full wizard"
            fi
        else
            log_warn "Could not resolve account ID — continuing with full wizard"
        fi
    fi

    if check_cloudflare_config; then
        log_info "Cloudflare Tunnel configuration already exists"
        if ! prompt_yes_no "Reconfigure Cloudflare Tunnel?" "n"; then
            return 0
        fi
    fi

    # If an API token is already set (collected during domain config), go straight to API setup
    local _api_token_check
    _api_token_check=$(grep "^CLOUDFLARE_API_TOKEN=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || [[ -n "$_api_token_check" ]]; then
        log_info "Cloudflare API token detected — starting automated tunnel setup..."
        setup_tunnel_with_api
        return $?
    fi

    # No token — offer to skip or enter token now
    echo ""
    echo "No Cloudflare API token found."
    echo "  • Enter a token now to set up the tunnel automatically, or"
    echo "  • Skip and run './setup.sh --cloudflare-only' later."
    echo ""
    echo "  Token permissions needed: Account:Cloudflare Tunnel:Edit + Zone:DNS:Edit"
    echo "  Create at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""

    local method
    read -p "? Enter API token now, or skip? [token/skip] [skip]: " -r method </dev/tty
    method=${method:-skip}

    if [[ "$method" == "skip" || "$method" == "s" ]]; then
        log_info "Skipping Cloudflare Tunnel setup"
        log_info "You can configure it later by running: ./setup.sh --cloudflare-only"
        return 0
    else
        # Treat any non-skip input as the token itself
        if [[ "$method" != "token" && "$method" != "t" ]]; then
            export CLOUDFLARE_API_TOKEN="$method"
        fi
        setup_tunnel_with_api
        return $?
    fi
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

    # 1. Domain name — use what's already in .env if set, only prompt if missing
    local current_domain
    current_domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    local domain
    if [[ -n "$current_domain" && "$current_domain" != "localhost" ]]; then
        domain="$current_domain"
        log_info "Using domain: $domain"
    else
        echo "Enter the domain name you want to use for external access."
        echo "This domain must be added to your Cloudflare account."
        echo ""
        domain=$(prompt_input "Domain name (e.g., example.com)" "")
        if [[ -z "$domain" ]]; then
            log_error "Domain name is required for Cloudflare Tunnel"
            return 1
        fi
        sed -i "s|^BASE_DOMAIN=.*|BASE_DOMAIN=$domain|" "$stack_dir/.env"
    fi
    export CLOUDFLARE_DOMAIN="$domain"

    # 2. Tunnel name — use existing or default without prompting
    local tunnel_name="weekendstack-tunnel"
    local existing_tunnel_name
    existing_tunnel_name=$(grep "^CLOUDFLARE_TUNNEL_NAME=" "$stack_dir/.env" 2>/dev/null | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    if [[ -n "$existing_tunnel_name" ]]; then
        tunnel_name="$existing_tunnel_name"
    fi
    log_info "Tunnel name: $tunnel_name"

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
    
    if ! _cf_verify_token "$api_token"; then
        log_error "API token validation failed"
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
            if ! _cf_verify_token "$api_token"; then
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
        local max_token_attempts=3
        local attempt=1
        while [[ $attempt -le $max_token_attempts ]]; do
            log_step "Fetching tunnel connector token (attempt $attempt/$max_token_attempts)..."
            tunnel_token=$(cf_get_tunnel_token "$account_id" "$tunnel_id" 2>/dev/null)
            if [[ $? -eq 0 && -n "$tunnel_token" ]]; then
                break
            fi
            log_warn "Token fetch attempt $attempt failed — retrying in 3s..."
            sleep 3
            attempt=$((attempt + 1))
        done

        if [[ -n "$tunnel_token" ]]; then
            if grep -q "^CLOUDFLARE_TUNNEL_TOKEN=" "$env_file"; then
                sed -i "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token|" "$env_file"
            else
                echo "CLOUDFLARE_TUNNEL_TOKEN=$tunnel_token" >> "$env_file"
            fi
            log_success "Saved tunnel token to .env"
        else
            log_error "Could not retrieve tunnel connector token after $max_token_attempts attempts"
            log_warn "Tunnel is created but the connector token is missing."
            log_warn "The cloudflare-tunnel container will not start until a token is available."
            log_info "To fix this later, run: ./setup.sh --cloudflare-only"
            # Explicitly mark tunnel as disabled so setup.sh gives a clear message
            sed -i "s|^CLOUDFLARE_TUNNEL_ENABLED=.*|CLOUDFLARE_TUNNEL_ENABLED=false|" "$env_file" 2>/dev/null || true
            return 1
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
