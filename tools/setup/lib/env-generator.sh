#!/bin/bash
# Environment file generator with interactive prompts
# Collects all configuration, then generates .env at the end

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Safe function to update .env variable (handles all special characters)
update_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env_file="$3"
    
    # Use awk to safely replace the line - avoids all escaping issues
    awk -v var="$var_name" -v val="$var_value" '
        $0 ~ "^" var "=" { print var "=" val; next }
        { print }
    ' "$env_file" > "${env_file}.tmp" && mv "${env_file}.tmp" "$env_file"
}

# Progress tracking
show_progress() {
    local current=$1
    local total=$2
    local section=$3
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  Configuration Step $current of $total${NC}"
    echo -e "${BOLD}${CYAN}  $section${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Update profiles in existing .env without reconfiguring
update_env_profiles_only() {
    local env_file="${SCRIPT_DIR}/.env"
    local selected_profiles=("$@")
    
    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found - running full configuration"
        return 1
    fi
    
    clear
    log_header "Updating Service Profiles"
    
    echo "Existing configuration detected in .env"
    echo ""
    echo "Your current settings will be preserved."
    echo "Only the selected service profiles will be updated."
    echo ""
    
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    
    log_step "Updating COMPOSE_PROFILES to: $profiles_string"
    update_env_var "COMPOSE_PROFILES" "$profiles_string" "$env_file"
    
    # Update metadata
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    update_env_var "SETUP_DATE" "$timestamp" "$env_file"
    update_env_var "SELECTED_PROFILES" "$profiles_string" "$env_file"
    
    log_success "Profiles updated successfully"
    echo ""
    log_info "All other settings preserved from existing .env"
    log_info "To reconfigure all settings, run: ./setup.sh --reconfigure"
    echo ""
    echo "Press Enter to continue..."
    read -r
    
    return 0
}

generate_env_interactive() {
    local env_example="${SCRIPT_DIR}/.env.example"
    local env_file="${SCRIPT_DIR}/.env"
    local selected_profiles=("$@")
    
    # Check if .env exists and we should just update profiles
    if [[ -f "$env_file" ]] && [[ "${FORCE_RECONFIGURE:-false}" != "true" ]]; then
        log_info "Existing .env configuration found"
        echo ""
        
        if prompt_yes_no "Keep existing configuration and only update service profiles?" "y"; then
            if update_env_profiles_only "${selected_profiles[@]}"; then
                return 0
            fi
            # If update failed, fall through to full wizard
        fi
        
        # User chose to reconfigure or update failed
        clear
    fi
    
    clear
    log_header "WeekendStack Configuration Wizard"
    
    echo "This wizard will guide you through configuring your WeekendStack deployment."
    echo "We'll collect all necessary information, then generate your .env file at the end."
    echo ""
    echo -e "${BOLD}Total Steps: 5${NC}"
    echo "  1. System Settings (hostname, IP, timezone)"
    echo "  2. Domain Configuration (local and external access)"  
    echo "  3. Admin Credentials (default username/password)"
    echo "  4. File Storage Paths (where to store data)"
    echo "  5. Review & Generate (create .env file)"
    echo ""
    
    if ! prompt_yes_no "Ready to begin?" "y"; then
        log_error "Setup cancelled by user"
        return 1
    fi
    
    # Backup existing .env if it exists
    if [[ -f "$env_file" ]]; then
        clear
        log_warn "Existing .env file found"
        if prompt_yes_no "Create backup before generating new .env?" "y"; then
            backup_file "$env_file"
        fi
    fi
    
    # ========================================================================
    # STEP 1: System Settings
    # ========================================================================
    clear
    show_progress 1 5 "System Settings"
    
    echo "This section configures basic system identification and network settings."
    echo ""
    
    # Computer name
    local default_hostname=$(hostname)
    local computer_name=$(prompt_input "Computer/host name (identifies this system)" "$default_hostname")
    
    # Host IP
    echo ""
    echo "Enter the IP address of this host on your local network."
    echo "This is used for local DNS configuration and service discovery."
    echo ""
    local detected_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    local host_ip
    while true; do
        host_ip=$(prompt_input "Host IP address" "$detected_ip")
        if validate_ip "$host_ip"; then
            break
        else
            log_error "Invalid IP address format"
        fi
    done
    
    # Timezone
    echo ""
    echo "Enter your timezone (used for container timestamps and scheduling)."
    echo ""
    local detected_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
    local timezone=$(prompt_input "Timezone" "$detected_tz")
    
    # PUID/PGID
    echo ""
    echo "File permissions: Docker containers need to run with specific user/group IDs"
    echo "to properly access files on the host. Using your current user is recommended."
    echo ""
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    log_info "Current user: UID=$current_uid GID=$current_gid"
    echo ""
    
    local puid pgid
    if prompt_yes_no "Use current user's UID/GID for file permissions?" "y"; then
        puid=$current_uid
        pgid=$current_gid
    else
        puid=$(prompt_input "PUID" "1000")
        pgid=$(prompt_input "PGID" "1000")
    fi
    
    log_success "System settings configured"
    echo ""
    echo "Press Enter to continue to domain configuration..."
    read -r
    
    # ========================================================================
    # STEP 2: Domain Configuration  
    # ========================================================================
    clear
    show_progress 2 5 "Domain Configuration"
    
    echo "WeekendStack services are accessed via domain names."
    echo ""
    echo "You'll configure:"
    echo "  1. Local domain for LAN access (always required)"
    echo "  2. External domain for internet access (optional, requires Cloudflare Tunnel)"
    echo ""
    
    # Local domain
    echo -e "${BOLD}Local Network Access:${NC}"
    echo ""
    echo "Choose a domain suffix for accessing services on your local network."
    echo "This requires either Pi-hole DNS or manual /etc/hosts entries."
    echo ""
    echo "Examples:"
    echo "  • 'lab'   → Services accessible at https://service.lab"
    echo "  • 'home'  → Services accessible at https://service.home"
    echo "  • 'local' → Services accessible at https://service.local"
    echo ""
    
    local lab_domain=$(prompt_input "Local domain suffix (without leading dot)" "lab")
    
    echo ""
    log_success "Local services will be accessible at: https://service.$lab_domain"
    log_info "Examples: https://coder.$lab_domain, https://paperless.$lab_domain"
    echo ""
    
    # External domain (Cloudflare Tunnel)
    echo -e "${BOLD}External Internet Access (Optional):${NC}"
    echo ""
    echo "If you want to access services from anywhere on the internet, you can"
    echo "set up Cloudflare Tunnel. This requires a domain name you control."
    echo ""
    
    local base_domain="localhost"
    
    if prompt_yes_no "Enable external access via Cloudflare Tunnel?" "n"; then
        echo ""
        echo "Enter your domain name (e.g., mystack.example.com or example.com):"
        echo ""
        
        while true; do
            base_domain=$(prompt_input "External domain" "")
            
            if [[ -z "$base_domain" ]]; then
                log_warn "Skipping external access (no domain provided)"
                base_domain="localhost"
                break
            elif validate_domain "$base_domain"; then
                log_success "External services will be accessible at: https://service.$base_domain"
                break
            else
                log_error "Invalid domain format (e.g., example.com or sub.example.com)"
            fi
        done
    else
        log_info "External access disabled - services will only be available on local network"
    fi
    
    log_success "Domain configuration complete"
    echo ""
    echo "Press Enter to continue to admin credentials..."
    read -r
    
    # ========================================================================
    # STEP 3: Admin Credentials
    # ========================================================================
    clear
    show_progress 3 5 "Default Admin Credentials"
    
    echo "Many services (NocoDB, Paperless, Postiz, etc.) support auto-provisioning"
    echo "with default credentials. These will be used during initial setup."
    echo ""
    log_warn "IMPORTANT: These are default credentials. Change them after first login!"
    echo ""
    echo "You can either:"
    echo "  • Set custom credentials now"
    echo "  • Use defaults (username: admin, auto-generated password)"
    echo ""
    
    local admin_user="admin"
    local admin_email="admin@example.com"
    local admin_password=""  # Will be auto-generated
    
    if prompt_yes_no "Set custom admin credentials now?" "n"; then
        admin_user=$(prompt_input "Admin username" "admin")
        
        echo ""
        while true; do
            admin_email=$(prompt_input "Admin email" "admin@example.com")
            if validate_email "$admin_email" || [[ "$admin_email" == "admin@example.com" ]]; then
                break
            else
                log_error "Invalid email format"
            fi
        done
        
        echo ""
        echo "Password options:"
        echo "  • Enter custom password"
        echo "  • Auto-generate secure random password (recommended)"
        echo ""
        if prompt_yes_no "Set custom admin password?" "n"; then
            admin_password=$(prompt_password "Admin password")
        fi
    fi
    
    if [[ -z "$admin_password" ]]; then
        log_info "Will use auto-generated random password (you'll see it in .env at the end)"
    fi
    
    log_success "Admin credentials configured"
    echo ""
    echo "Press Enter to continue to file storage configuration..."
    read -r
    
    # ========================================================================
    # STEP 4: File Storage Paths
    # ========================================================================
    clear
    show_progress 4 5 "File Storage Paths"
    
    echo "WeekendStack uses three base directories for data storage:"
    echo ""
    echo "  1. FILES_BASE_DIR  - User content (documents, media, photos)"
    echo "  2. DATA_BASE_DIR   - Application databases and state"
    echo "  3. CONFIG_BASE_DIR - Service configuration files"
    echo ""
    echo "Default: Relative paths (./files, ./data, ./config)"
    echo "Advanced: Can use absolute paths or NFS mounts (e.g., /mnt/storage)"
    echo ""
    
    local files_dir="./files"
    local data_dir="./data"
    local config_dir="./config"
    local workspace_dir="/mnt/workspace"
    local ssh_key_dir="\${CONFIG_BASE_DIR}/ssh"
    
    if prompt_yes_no "Customize storage paths?" "n"; then
        files_dir=$(prompt_input "User files directory" "./files")
        data_dir=$(prompt_input "Application data directory" "./data")
        config_dir=$(prompt_input "Configuration directory" "./config")
        
        echo ""
        echo "Coder workspace directory (must be absolute path):"
        workspace_dir=$(prompt_input "Workspace directory" "/mnt/workspace")
        
        while [[ ! "$workspace_dir" =~ ^/ ]]; do
            log_error "Workspace directory must be an absolute path (start with /)"
            workspace_dir=$(prompt_input "Workspace directory" "/mnt/workspace")
        done
        
        if prompt_yes_no "Customize SSH key directory?" "n"; then
            ssh_key_dir=$(prompt_input "SSH key directory" "\${CONFIG_BASE_DIR}/ssh")
        fi
    fi
    
    log_success "Storage paths configured"
    echo ""
    echo "Press Enter to review and generate your .env file..."
    read -r
    
    # ========================================================================
    # STEP 5: Review & Generate
    # ========================================================================
    clear
    show_progress 5 5 "Review & Generate Configuration"
    
    echo "Configuration summary:"
    echo ""
    echo -e "${BOLD}System Settings:${NC}"
    echo "  Computer Name:    $computer_name"
    echo "  Host IP:          $host_ip"
    echo "  Timezone:         $timezone"
    echo "  User Permissions: UID=$puid GID=$pgid"
    echo ""
    echo -e "${BOLD}Domains:${NC}"
    echo "  Local Domain:     .$lab_domain"
    if [[ "$base_domain" != "localhost" ]]; then
        echo "  External Domain:  $base_domain (Cloudflare Tunnel enabled)"
    else
        echo "  External Access:  Disabled (local network only)"
    fi
    echo ""
    echo -e "${BOLD}Admin Credentials:${NC}"
    echo "  Username:         $admin_user"
    echo "  Email:            $admin_email"
    if [[ -n "$admin_password" ]]; then
        echo "  Password:         (custom - set)"
    else
        echo "  Password:         (auto-generated)"
    fi
    echo ""
    echo -e "${BOLD}Storage:${NC}"
    echo "  Files:            $files_dir"
    echo "  Data:             $data_dir"
    echo "  Config:           $config_dir"
    echo "  Workspace:        $workspace_dir"
    echo ""
    echo -e "${BOLD}Profiles:${NC}"
    echo "  Selected:         ${selected_profiles[*]}"
    echo ""
    
    if ! prompt_yes_no "Generate .env file with these settings?" "y"; then
        log_error "Configuration cancelled by user"
        return 1
    fi
    
    # ========================================================================
    # Generate .env file
    # ========================================================================
    log_step "Generating .env file with secure random secrets..."
    
    # Step 1: Generate base file from template
    if ! "${SCRIPT_DIR}/tools/env-template-gen.sh" >/dev/null 2>&1; then
        log_error "Failed to generate .env from template"
        return 1
    fi
    
    # Step 2: Apply all collected configuration using safe update function
    log_step "Applying configuration values..."
    
    update_env_var "COMPUTER_NAME" "$computer_name" "$env_file"
    update_env_var "HOST_IP" "$host_ip" "$env_file"
    update_env_var "TZ" "$timezone" "$env_file"
    update_env_var "PUID" "$puid" "$env_file"
    update_env_var "PGID" "$pgid" "$env_file"
    update_env_var "LAB_DOMAIN" "$lab_domain" "$env_file"
    update_env_var "BASE_DOMAIN" "$base_domain" "$env_file"
    update_env_var "DEFAULT_ADMIN_USER" "$admin_user" "$env_file"
    update_env_var "DEFAULT_ADMIN_EMAIL" "$admin_email" "$env_file"
    
    # Only set custom password if provided
    if [[ -n "$admin_password" ]]; then
        update_env_var "DEFAULT_ADMIN_PASSWORD" "$admin_password" "$env_file"
    fi
    
    update_env_var "FILES_BASE_DIR" "$files_dir" "$env_file"
    update_env_var "DATA_BASE_DIR" "$data_dir" "$env_file"
    update_env_var "CONFIG_BASE_DIR" "$config_dir" "$env_file"
    update_env_var "WORKSPACE_DIR" "$workspace_dir" "$env_file"
    update_env_var "SSH_KEY_DIR" "$ssh_key_dir" "$env_file"
    
    # Profile configuration
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    update_env_var "COMPOSE_PROFILES" "$profiles_string" "$env_file"
    
    # Add setup metadata
    add_setup_metadata "$env_file" "${selected_profiles[@]}"
    
    log_success ".env file created successfully!"
    echo ""
    log_info "Your configuration has been saved to: $env_file"
    
    # Show generated admin password if it was auto-generated
    if [[ -z "$admin_password" ]]; then
        local generated_password=$(grep "^DEFAULT_ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2)
        echo ""
        log_warn "IMPORTANT - Save this default admin password:"
        echo ""
        echo -e "${BOLD}  Username: $admin_user${NC}"
        echo -e "${BOLD}  Password: $generated_password${NC}"
        echo ""
        log_warn "Change this password after your first login to each service!"
    fi
    
    echo ""
    echo "Press Enter to continue with setup..."
    read -r
}

add_setup_metadata() {
    local env_file="$1"
    shift
    local selected_profiles=("$@")
    
    # Add setup metadata to .env file
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    
    # Check if metadata section exists
    if ! grep -q "# Setup Metadata" "$env_file"; then
        cat >> "$env_file" << EOF

# =============================================================================
# Setup Metadata (Generated by setup.sh)
# =============================================================================
SETUP_COMPLETED=true
SETUP_DATE=$timestamp
SELECTED_PROFILES=$profiles_string
EOF
    else
        update_env_var "SETUP_COMPLETED" "true" "$env_file"
        update_env_var "SETUP_DATE" "$timestamp" "$env_file"
        update_env_var "SELECTED_PROFILES" "$profiles_string" "$env_file"
    fi
}

generate_env_quick() {
    local env_file="${SCRIPT_DIR}/.env"
    local selected_profiles=("$@")
    
    log_header "Quick Environment Setup"
    
    # Backup existing .env
    if [[ -f "$env_file" ]]; then
        backup_file "$env_file"
    fi
    
    # Generate from template
    log_step "Generating .env with defaults..."
    if ! "${SCRIPT_DIR}/tools/env-template-gen.sh" >/dev/null 2>&1; then
        log_error "Failed to generate .env from template"
        return 1
    fi
    
    # Auto-detect and set critical values
    local hostname=$(hostname)
    local detected_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    local detected_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    
    update_env_var "COMPUTER_NAME" "$hostname" "$env_file"
    update_env_var "HOST_IP" "$detected_ip" "$env_file"
    update_env_var "TZ" "$detected_tz" "$env_file"
    update_env_var "PUID" "$current_uid" "$env_file"
    update_env_var "PGID" "$current_gid" "$env_file"
    
    # Set profiles
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    update_env_var "COMPOSE_PROFILES" "$profiles_string" "$env_file"
    
    # Add metadata
    add_setup_metadata "$env_file" "${selected_profiles[@]}"
    
    log_success "Quick environment setup complete"
    log_info "Computer: $hostname"
    log_info "Host IP: $detected_ip"
    log_info "Profiles: $profiles_string"
}

# Export functions
export -f generate_env_interactive generate_env_quick
export -f add_setup_metadata show_progress update_env_profiles_only update_env_var
