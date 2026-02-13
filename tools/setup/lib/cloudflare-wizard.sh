#!/bin/bash
# Cloudflare Tunnel setup wizard
# Guides users through creating and configuring Cloudflare Tunnel

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

check_cloudflare_config() {
    local stack_dir="${SCRIPT_DIR}/.."
    local config_file="$stack_dir/config/cloudflare/config.yml"
    local creds_pattern="$stack_dir/config/cloudflare/*.json"
    
    if [[ -f "$config_file" ]] && compgen -G "$creds_pattern" > /dev/null; then
        return 0
    fi
    
    return 1
}

show_cloudflare_intro() {
    log_header "Cloudflare Tunnel Setup"
    
    echo "Cloudflare Tunnel provides secure access to your services from the internet"
    echo "without port forwarding or exposing your home IP address."
    echo ""
    echo "Benefits:"
    echo "  • No port forwarding required"
    echo "  • DDoS protection via Cloudflare"
    echo "  • Free SSL/TLS certificates"
    echo "  • Access services from anywhere"
    echo ""
    echo "Requirements:"
    echo "  • Cloudflare account (free tier is fine)"
    echo "  • Domain name added to Cloudflare"
    echo "  • Cloudflared CLI installed (optional, can use web UI)"
    echo ""
}

setup_cloudflare_tunnel() {
    show_cloudflare_intro
    
    if check_cloudflare_config; then
        log_info "Cloudflare Tunnel configuration already exists"
        if ! prompt_yes_no "Reconfigure Cloudflare Tunnel?" "n"; then
            return 0
        fi
    fi
    
    if ! prompt_yes_no "Set up Cloudflare Tunnel now?" "y"; then
        log_info "Skipping Cloudflare Tunnel setup"
        log_info "You can configure it manually later - see docs/cloudflare-tunnel-setup.md"
        return 0
    fi
    
    # Check if cloudflared is installed
    local use_cli=false
    if check_command cloudflared; then
        log_success "cloudflared CLI detected"
        if prompt_yes_no "Use cloudflared CLI for setup?" "y"; then
            use_cli=true
        fi
    fi
    
    if $use_cli; then
        setup_tunnel_with_cli
    else
        setup_tunnel_manual
    fi
}

setup_tunnel_with_cli() {
    log_header "Cloudflare Tunnel Setup (CLI Method)"
    
    local stack_dir="${SCRIPT_DIR}/.."
    local tunnel_name
    local domain
    
    # Get domain from .env
    if [[ -f "$stack_dir/.env" ]]; then
        domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2)
    fi
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        echo ""
        log_warn "BASE_DOMAIN not set in .env or set to localhost"
        domain=$(prompt_input "Domain name for tunnel (must be in your Cloudflare account)" "")
        
        if [[ -z "$domain" ]]; then
            log_error "Domain name is required for Cloudflare Tunnel"
            return 1
        fi
        
        # Update .env
        sed -i "s/^BASE_DOMAIN=.*/BASE_DOMAIN=$domain/" "$stack_dir/.env"
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
    local creds_dest="$stack_dir/config/cloudflare/$tunnel_id.json"
    
    if [[ -f "$creds_source" ]]; then
        cp "$creds_source" "$creds_dest"
        chmod 600 "$creds_dest"
        log_success "Copied credentials to config/cloudflare/"
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
    
    local stack_dir="${SCRIPT_DIR}/.."
    local tunnel_name
    local tunnel_id
    local domain
    
    tunnel_name=$(prompt_input "Tunnel name (as shown in dashboard)" "weekendstack-tunnel")
    tunnel_id=$(prompt_input "Tunnel ID (UUID from dashboard)" "")
    
    if [[ -z "$tunnel_id" ]]; then
        log_error "Tunnel ID is required"
        return 1
    fi
    
    # Get domain
    if [[ -f "$stack_dir/.env" ]]; then
        domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2)
    fi
    
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        domain=$(prompt_input "Your domain name" "")
        sed -i "s/^BASE_DOMAIN=.*/BASE_DOMAIN=$domain/" "$stack_dir/.env"
    fi
    
    # Get credentials
    echo ""
    echo "How do you want to provide credentials?"
    local creds_method
    creds_method=$(prompt_select "Credentials method:" "JSON file path" "Paste JSON content" "Tunnel token")
    
    case $creds_method in
        0) # File path
            local creds_file
            creds_file=$(prompt_input "Path to credentials JSON file" "")
            
            if [[ ! -f "$creds_file" ]]; then
                log_error "File not found: $creds_file"
                return 1
            fi
            
            cp "$creds_file" "$stack_dir/config/cloudflare/$tunnel_id.json"
            chmod 600 "$stack_dir/config/cloudflare/$tunnel_id.json"
            log_success "Copied credentials file"
            ;;
            
        1) # Paste JSON
            log_info "Paste the JSON credentials (press Ctrl+D when done):"
            cat > "$stack_dir/config/cloudflare/$tunnel_id.json"
            chmod 600 "$stack_dir/config/cloudflare/$tunnel_id.json"
            log_success "Saved credentials file"
            ;;
            
        2) # Tunnel token
            log_warn "Tunnel token method requires different configuration"
            log_info "For now, use JSON credentials. Token support coming soon."
            return 1
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
    local stack_dir="${SCRIPT_DIR}/.."
    local config_file="$stack_dir/config/cloudflare/config.yml"
    
    log_step "Creating tunnel configuration..."
    
    # Backup existing config
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file"
    fi
    
    cat > "$config_file" << EOF
tunnel: $tunnel_name
credentials-file: /etc/cloudflared/.cloudflared/$tunnel_id.json

ingress:
  # Route all subdomains to Traefik
  - hostname: "*.$domain"
    service: https://traefik:443
    originRequest:
      noTLSVerify: true  # Trust Traefik's self-signed cert
  
  # Catch-all rule (required)
  - service: http_status:404
EOF
    
    log_success "Created config: config/cloudflare/config.yml"
}

update_env_cloudflare() {
    local tunnel_name="$1"
    local tunnel_id="$2"
    local domain="$3"
    local stack_dir="${SCRIPT_DIR}/.."
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
}

display_tunnel_status() {
    local tunnel_name="$1"
    
    echo ""
    echo "${BOLD}Next Steps:${NC}"
    echo "1. Start the tunnel: docker compose --profile networking up -d cloudflared"
    echo "2. Check tunnel status: docker logs cloudflare-tunnel"
    echo "3. Test external access: https://yourservice.$domain"
    echo ""
    echo "Your services will be accessible via Cloudflare Tunnel at:"
    echo "  https://*.$domain → Traefik → Internal services"
    echo ""
}

test_tunnel_connectivity() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    if [[ ! -f "$stack_dir/.env" ]]; then
        log_error "No .env file found"
        return 1
    fi
    
    local domain=$(grep "^BASE_DOMAIN=" "$stack_dir/.env" | cut -d'=' -f2)
    
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
export -f setup_tunnel_with_cli setup_tunnel_manual create_tunnel_config
export -f update_env_cloudflare display_tunnel_status test_tunnel_connectivity
