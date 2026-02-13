#!/bin/bash
# Environment file generator with interactive prompts
# Extends the existing env-template-gen.sh with user customization

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

generate_env_interactive() {
    local env_example="${SCRIPT_DIR}/../.env.example"
    local env_file="${SCRIPT_DIR}/../.env"
    local selected_profiles=("$@")
    
    log_header "Environment Configuration"
    
    # Backup existing .env
    if [[ -f "$env_file" ]]; then
        log_warn "Existing .env file found"
        if prompt_yes_no "Create backup before generating new .env?" "y"; then
            backup_file "$env_file"
        fi
    fi
    
    # Start with template generation (existing script)
    log_step "Generating .env from template with secure secrets..."
    if ! "${SCRIPT_DIR}/../env-template-gen.sh" >/dev/null 2>&1; then
        log_error "Failed to generate .env from template"
        return 1
    fi
    log_success ".env generated with secure random secrets"
    
    # Now customize with user input
    log_header "System Configuration"
    
    # Computer name
    local computer_name
    local default_hostname=$(hostname)
    computer_name=$(prompt_input "Computer/host name" "$default_hostname")
    sed -i "s/^COMPUTER_NAME=.*/COMPUTER_NAME=$computer_name/" "$env_file"
    
    # Computer type
    echo ""
    local computer_type
    computer_type=$(prompt_select "Computer type:" "workstation" "server" "homelab")
    case $computer_type in
        0) sed -i "s/^COMPUTER_TYPE=.*/COMPUTER_TYPE=workstation/" "$env_file" ;;
        1) sed -i "s/^COMPUTER_TYPE=.*/COMPUTER_TYPE=server/" "$env_file" ;;
        2) sed -i "s/^COMPUTER_TYPE=.*/COMPUTER_TYPE=homelab/" "$env_file" ;;
    esac
    
    # Host IP
    echo ""
    local host_ip
    local detected_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    
    while true; do
        host_ip=$(prompt_input "Host IP address (for local DNS)" "$detected_ip")
        if validate_ip "$host_ip"; then
            sed -i "s/^HOST_IP=.*/HOST_IP=$host_ip/" "$env_file"
            break
        else
            log_error "Invalid IP address format"
        fi
    done
    
    # Timezone
    echo ""
    local timezone
    local detected_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
    timezone=$(prompt_input "Timezone" "$detected_tz")
    sed -i "s|^TZ=.*|TZ=$timezone|" "$env_file"
    
    # PUID/PGID
    echo ""
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    log_info "Current user: UID=$current_uid GID=$current_gid"
    
    if prompt_yes_no "Use current user's UID/GID for file permissions?" "y"; then
        sed -i "s/^PUID=.*/PUID=$current_uid/" "$env_file"
        sed -i "s/^PGID=.*/PGID=$current_gid/" "$env_file"
    else
        local puid=$(prompt_input "PUID" "1000")
        local pgid=$(prompt_input "PGID" "1000")
        sed -i "s/^PUID=.*/PUID=$puid/" "$env_file"
        sed -i "s/^PGID=.*/PGID=$pgid/" "$env_file"
    fi
    
    # Domain configuration
    configure_domains "$env_file"
    
    # Admin credentials
    configure_admin_credentials "$env_file"
    
    # File paths
    if prompt_yes_no "Customize file storage locations?" "n"; then
        configure_file_paths "$env_file"
    fi
    
    # Profile configuration
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=$profiles_string/" "$env_file"
    
    # Add setup metadata
    add_setup_metadata "$env_file" "${selected_profiles[@]}"
    
    log_success "Environment configuration complete"
}

configure_domains() {
    local env_file="$1"
    
    log_header "Domain Configuration"
    
    echo "WeekendStack supports two domain types:"
    echo "  1. Local domain (.lab by default) - for LAN access"
    echo "  2. External domain - for internet access via Cloudflare Tunnel"
    echo ""
    
    # Local domain
    local lab_domain
    lab_domain=$(prompt_input "Local domain suffix (without dot)" "lab")
    sed -i "s/^LAB_DOMAIN=.*/LAB_DOMAIN=$lab_domain/" "$env_file"
    
    echo ""
    log_info "Services will be accessible at: service.$lab_domain"
    log_info "Example: https://coder.$lab_domain"
    echo ""
    
    # External domain
    local base_domain
    echo "External domain (leave as 'localhost' if not using Cloudflare Tunnel):"
    base_domain=$(prompt_input "External domain" "localhost")
    
    if [[ "$base_domain" != "localhost" ]]; then
        while ! validate_domain "$base_domain"; do
            log_error "Invalid domain format"
            base_domain=$(prompt_input "External domain" "localhost")
        done
    fi
    
    sed -i "s/^BASE_DOMAIN=.*/BASE_DOMAIN=$base_domain/" "$env_file"
    
    if [[ "$base_domain" != "localhost" ]]; then
        log_info "External services will be accessible at: service.$base_domain"
        echo ""
    fi
}

configure_admin_credentials() {
    local env_file="$1"
    
    log_header "Default Admin Credentials"
    
    echo "These credentials will be used for services that support auto-provisioning"
    echo "(NocoDB, Paperless-ngx, Postiz, etc.)"
    echo ""
    log_warn "IMPORTANT: Change these after first login for production use!"
    echo ""
    
    if prompt_yes_no "Set custom admin credentials now?" "y"; then
        # Admin username
        local admin_user
        admin_user=$(prompt_input "Admin username" "admin")
        sed -i "s/^DEFAULT_ADMIN_USER=.*/DEFAULT_ADMIN_USER=$admin_user/" "$env_file"
        
        # Admin email
        local admin_email
        while true; do
            admin_email=$(prompt_input "Admin email" "admin@example.com")
            if validate_email "$admin_email" || [[ "$admin_email" == "admin@example.com" ]]; then
                sed -i "s/^DEFAULT_ADMIN_EMAIL=.*/DEFAULT_ADMIN_EMAIL=$admin_email/" "$env_file"
                break
            else
                log_error "Invalid email format"
            fi
        done
        
        # Admin password
        echo ""
        if prompt_yes_no "Set custom admin password? (or use generated random password)" "n"; then
            local admin_password
            admin_password=$(prompt_password "Admin password" 16)
            sed -i "s/^DEFAULT_ADMIN_PASSWORD=.*/DEFAULT_ADMIN_PASSWORD=$admin_password/" "$env_file"
        else
            log_info "Using generated random password (check .env file)"
        fi
    else
        log_info "Using default credentials: admin / <random generated password>"
        log_warn "Check .env file for generated password"
    fi
    
    echo ""
}

configure_file_paths() {
    local env_file="$1"
    
    log_header "File Storage Paths"
    
    echo "WeekendStack uses three base directories:"
    echo "  1. FILES_BASE_DIR  - User data (documents, media, photos)"
    echo "  2. DATA_BASE_DIR   - Application databases and state"
    echo "  3. CONFIG_BASE_DIR - Configuration files"
    echo ""
    echo "Default: ./files, ./data, ./config (relative to stack directory)"
    echo ""
    
    # FILES_BASE_DIR
    local files_dir
    files_dir=$(prompt_input "User files directory" "./files")
    sed -i "s|^FILES_BASE_DIR=.*|FILES_BASE_DIR=$files_dir|" "$env_file"
    
    # DATA_BASE_DIR
    local data_dir
    data_dir=$(prompt_input "Application data directory" "./data")
    sed -i "s|^DATA_BASE_DIR=.*|DATA_BASE_DIR=$data_dir|" "$env_file"
    
    # CONFIG_BASE_DIR
    local config_dir
    config_dir=$(prompt_input "Configuration directory" "./config")
    sed -i "s|^CONFIG_BASE_DIR=.*|CONFIG_BASE_DIR=$config_dir|" "$env_file"
    
    echo ""
    
    # WORKSPACE_DIR (must be absolute)
    log_info "Coder workspace directory (must be absolute path):"
    local workspace_dir
    workspace_dir=$(prompt_input "Workspace directory" "/mnt/workspace")
    
    while [[ ! "$workspace_dir" =~ ^/ ]]; do
        log_error "Workspace directory must be an absolute path"
        workspace_dir=$(prompt_input "Workspace directory" "/mnt/workspace")
    done
    
    sed -i "s|^WORKSPACE_DIR=.*|WORKSPACE_DIR=$workspace_dir|" "$env_file"
    
    # SSH_KEY_DIR (optional)
    if prompt_yes_no "Customize SSH key directory?" "n"; then
        local ssh_key_dir
        ssh_key_dir=$(prompt_input "SSH key directory" "\${CONFIG_BASE_DIR}/ssh")
        sed -i "s|^SSH_KEY_DIR=.*|SSH_KEY_DIR=$ssh_key_dir|" "$env_file"
    fi
    
    echo ""
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
        sed -i "s/^SETUP_COMPLETED=.*/SETUP_COMPLETED=true/" "$env_file"
        sed -i "s/^SETUP_DATE=.*/SETUP_DATE=$timestamp/" "$env_file"
        sed -i "s/^SELECTED_PROFILES=.*/SELECTED_PROFILES=$profiles_string/" "$env_file"
    fi
}

generate_env_quick() {
    local env_file="${SCRIPT_DIR}/../.env"
    local selected_profiles=("$@")
    
    log_header "Quick Environment Setup"
    
    # Backup existing .env
    if [[ -f "$env_file" ]]; then
        backup_file "$env_file"
    fi
    
    # Generate from template
    log_step "Generating .env with defaults..."
    if ! "${SCRIPT_DIR}/../env-template-gen.sh" >/dev/null 2>&1; then
        log_error "Failed to generate .env from template"
        return 1
    fi
    
    # Auto-detect and set critical values
    local hostname=$(hostname)
    local detected_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    local detected_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    
    sed -i "s/^COMPUTER_NAME=.*/COMPUTER_NAME=$hostname/" "$env_file"
    sed -i "s/^HOST_IP=.*/HOST_IP=$detected_ip/" "$env_file"
    sed -i "s|^TZ=.*|TZ=$detected_tz|" "$env_file"
    sed -i "s/^PUID=.*/PUID=$current_uid/" "$env_file"
    sed -i "s/^PGID=.*/PGID=$current_gid/" "$env_file"
    
    # Set profiles
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    sed -i "s/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=$profiles_string/" "$env_file"
    
    # Add metadata
    add_setup_metadata "$env_file" "${selected_profiles[@]}"
    
    log_success "Quick environment setup complete"
    log_info "Computer: $hostname"
    log_info "Host IP: $detected_ip"
    log_info "Profiles: $profiles_string"
}

# Export functions
export -f generate_env_interactive generate_env_quick
export -f configure_domains configure_admin_credentials configure_file_paths
export -f add_setup_metadata
