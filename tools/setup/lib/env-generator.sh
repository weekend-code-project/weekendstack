#!/bin/bash
# Environment file generator with interactive prompts
# Collects all configuration, then generates .env at the end

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Safe function to update .env variable (handles all special characters)
update_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env_file="$3"
    
    # Strip any newlines or carriage returns from value to prevent line injection  
    var_value="${var_value//$'\n'/}"
    var_value="${var_value//$'\r'/}"
    
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
    
    log_success "Profile update complete"
    
    return 0
}

generate_env_interactive() {
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
    show_progress 1 $total_steps "System Settings"
    
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
    
    # PUID/PGID - use current user by default
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    local puid=$current_uid
    local pgid=$current_gid
    
    log_success "System settings configured"
    
    # Check if networking profile is selected
    local has_networking=false
    local has_dev=false
    local has_ai=false
    local has_personal=false
    local has_automation=false
    for profile in "$@"; do
        if [[ "$profile" == "networking" ]] || [[ "$profile" == "all" ]]; then
            has_networking=true
        fi
        if [[ "$profile" == "dev" ]] || [[ "$profile" == "all" ]]; then
            has_dev=true
        fi
        if [[ "$profile" == "ai" ]] || [[ "$profile" == "all" ]]; then
            has_ai=true
        fi
        if [[ "$profile" == "personal" ]] || [[ "$profile" == "all" ]]; then
            has_personal=true
        fi
        if [[ "$profile" == "automation" ]] || [[ "$profile" == "all" ]]; then
            has_automation=true
        fi
    done
    
    # Calculate total steps based on selected profiles
    local total_steps=3  # Base: System Settings + Admin Credentials + File Storage
    if $has_networking; then
        ((total_steps++))  # Add Domain Configuration
    fi
    if $has_dev; then
        ((total_steps++))  # Add Git Service Selection
    fi
    if $has_ai; then
        ((total_steps++))  # Add AI Frontend Selection
    fi
    if $has_personal; then
        ((total_steps++))  # Add Personal Services Selection
    fi
    if $has_automation; then
        ((total_steps++))  # Add Automation Services Selection
    fi
    
    local lab_domain="lab"
    local base_domain="localhost"
    local _step=1  # running step counter
    
    # ========================================================================
    # STEP: Domain Configuration (only if networking profile selected)
    # ========================================================================
    if $has_networking; then
        _step=$((_step + 1))
        clear
        show_progress $_step $total_steps "Domain & Certificate Configuration"
        
        echo "You selected the networking profile which includes Traefik reverse proxy."
        echo ""
        echo "Configure your local domain suffix for accessing services:"
        echo ""
        echo "Examples:"
        echo "  • 'lab'   → Services accessible at https://service.lab"
        echo "  • 'home'  → Services accessible at https://service.home"
        echo "  • 'local' → Services accessible at https://service.local"
        echo ""
        
        lab_domain=$(prompt_input "Local domain suffix (without leading dot)" "lab")
        
        echo ""
        log_success "Services will be accessible at: https://service.$lab_domain"
        echo ""
        echo -e "${YELLOW}Note:${NC} Configure Pi-hole as your DNS server to resolve .$lab_domain,"
        echo "or manually add entries to /etc/hosts on each device."
        
        log_success "Domain configuration complete"
    fi
    
    # ========================================================================
    # STEP: Git Service Selection (only if dev profile selected)
    # ========================================================================
    local git_service="none"
    
    if $has_dev; then
        _step=$((_step + 1))
        clear
        show_progress $_step $total_steps "Git Service Selection"
        
        echo "You selected the development profile which includes git hosting."
        echo ""
        echo "Choose which git service to install:"
        echo ""
        echo "  1) None          - Skip git service (Coder IDE only)"
        echo "  2) Gitea         - Lightweight, fast, recommended (default)"
        if $has_networking; then
            echo "  3) GitLab        - Full CI/CD platform (requires Traefik)"
        fi
        echo ""
        
        local git_choice
        if $has_networking; then
            git_choice=$(prompt_input "Select git service [1-3]" "2")
        else
            git_choice=$(prompt_input "Select git service [1-2]" "2")
        fi
        
        case "$git_choice" in
            1)
                git_service="none"
                log_info "Git service disabled"
                ;;
            2)
                git_service="gitea"
                log_success "Gitea selected (lightweight git hosting)"
                ;;
            3)
                if $has_networking; then
                    git_service="gitlab"
                    log_success "GitLab selected (full CI/CD platform)"
                    log_warn "Note: GitLab requires HTTPS via Traefik. Ensure networking profile is enabled."
                else
                    log_error "GitLab requires the networking profile (Traefik). Defaulting to Gitea."
                    git_service="gitea"
                    log_success "Defaulting to Gitea"
                fi
                ;;
            *)
                log_warn "Invalid selection. Defaulting to Gitea."
                git_service="gitea"
                ;;
        esac
        
        log_success "Git service configuration complete"
    fi
    
    # ========================================================================
    # STEP: AI Chat Frontend Selection (only if ai profile selected)
    # ========================================================================
    local -a ai_frontends=()
    local use_gpu=false
    
    if $has_ai; then
        _step=$((_step + 1))
        clear
        show_progress $_step $total_steps "AI Services Configuration"
        
        # GPU detection
        if [[ "${GPU_AVAILABLE:-false}" == "true" ]]; then
            log_success "NVIDIA GPU detected — Ollama will use GPU acceleration"
            use_gpu=true
        else
            log_info "No GPU detected — Ollama will run on CPU"
        fi
        echo ""
        
        echo "You selected AI services. Ollama (LLM backend) and SearXNG (search) are"
        echo "always installed. Choose which chat frontend(s) to add:"
        echo ""
        echo "  1) Open WebUI     - Clean, polished interface for local models (recommended)"
        echo "  2) LibreChat      - Multi-provider (OpenAI, Anthropic, Ollama, and more)"
        echo "  3) AnythingLLM    - Document Q&A with RAG and vector DB"
        echo ""
        echo "Enter numbers space-separated (e.g. '1 2'), press Enter for all, or '0' for none:"
        echo ""
        
        local ai_frontend_input
        read -p "AI frontend selection [Enter=all]: " -r ai_frontend_input </dev/tty
        
        if [[ -z "$ai_frontend_input" ]]; then
            ai_frontends=("open-webui" "librechat" "anythingllm")
            log_info "Installing all AI frontends: Open WebUI, LibreChat, AnythingLLM"
        elif [[ "$ai_frontend_input" == "0" ]]; then
            ai_frontends=()
            log_info "No chat frontend selected — Ollama API only"
        else
            for n in $ai_frontend_input; do
                case "$n" in
                    1) ai_frontends+=("open-webui") ;;
                    2) ai_frontends+=("librechat") ;;
                    3) ai_frontends+=("anythingllm") ;;
                    *) log_warn "Unknown AI frontend option: $n (skipped)" ;;
                esac
            done
            if [[ ${#ai_frontends[@]} -gt 0 ]]; then
                log_success "Selected AI frontends: ${ai_frontends[*]}"
            else
                log_info "No valid frontend selected — Ollama API only"
            fi
        fi
        
        log_success "AI service configuration complete"
    fi
    
    # ========================================================================
    # STEP: Personal Services Selection (only if personal profile selected)
    # ========================================================================
    local -a personal_services=()
    
    if $has_personal; then
        _step=$((_step + 1))
        clear
        show_progress $_step $total_steps "Personal Services Selection"
        
        echo "You selected personal services. Choose which ones to install:"
        echo ""
        echo "  1) Mealie      - Recipe manager and meal planner"
        echo "  2) Firefly III - Personal finance and budget tracking"
        echo "  3) Wger        - Workout and fitness tracker"
        echo ""
        echo "Enter numbers space-separated (e.g. '1 3'), or press Enter to install all:"
        echo ""
        
        local personal_input
        read -p "Personal services [Enter=all]: " -r personal_input </dev/tty
        
        if [[ -z "$personal_input" ]]; then
            personal_services=("mealie" "firefly" "wger")
            log_info "Installing all personal services"
        else
            for n in $personal_input; do
                case "$n" in
                    1) personal_services+=("mealie") ;;
                    2) personal_services+=("firefly") ;;
                    3) personal_services+=("wger") ;;
                    *) log_warn "Unknown personal service option: $n (skipped)" ;;
                esac
            done
            if [[ ${#personal_services[@]} -gt 0 ]]; then
                log_success "Selected personal services: ${personal_services[*]}"
            else
                log_info "No personal services selected"
            fi
        fi
        
        log_success "Personal services configuration complete"
    fi
    
    # ========================================================================
    # STEP: Automation Services Selection (only if automation profile selected)
    # ========================================================================
    local -a automation_services=()
    
    if $has_automation; then
        _step=$((_step + 1))
        clear
        show_progress $_step $total_steps "Home Automation Services Selection"
        
        echo "You selected home automation services. Choose which ones to install:"
        echo ""
        echo "  1) Home Assistant  - Smart home automation platform"
        echo "  2) Node-RED        - Flow-based automation and IoT"
        echo ""
        echo "Enter numbers space-separated (e.g. '1 2'), or press Enter to install all:"
        echo ""
        
        local automation_input
        read -p "Automation services [Enter=all]: " -r automation_input </dev/tty
        
        if [[ -z "$automation_input" ]]; then
            automation_services=("homeassistant" "nodered")
            log_info "Installing all automation services"
        else
            for n in $automation_input; do
                case "$n" in
                    1) automation_services+=("homeassistant") ;;
                    2) automation_services+=("nodered") ;;
                    *) log_warn "Unknown automation service option: $n (skipped)" ;;
                esac
            done
            if [[ ${#automation_services[@]} -gt 0 ]]; then
                log_success "Selected automation services: ${automation_services[*]}"
            else
                log_info "No automation services selected"
            fi
        fi
        
        log_success "Automation services configuration complete"
    fi
    
    # ========================================================================
    # STEP: Admin Credentials (always shown)
    # ========================================================================
    _step=$((_step + 1))
    clear
    show_progress $_step $total_steps "Default Admin Credentials"
    
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
        admin_password=$(prompt_password "Admin password (or leave empty for auto-generated)")
    fi
    
    if [[ -z "$admin_password" ]]; then
        log_info "Will use auto-generated random password (you'll see it in .env at the end)"
    fi
    
    log_success "Admin credentials configured"
    
    # ========================================================================
    # STEP: File Storage Paths
    # ========================================================================
    _step=$((_step + 1))
    clear
    show_progress $_step $total_steps "File Storage Paths"
    
    echo "WeekendStack uses base directories for data storage:"
    echo ""
    echo "  1. FILES_BASE_DIR  - User content (documents, media, photos)"
    echo "  2. DATA_BASE_DIR   - Application databases and state"
    echo ""
    echo "Config files stay in ./config (part of repository)"
    echo ""
    echo "Default: Relative paths (./files, ./data)"
    echo "Advanced: Can use absolute paths or NFS mounts (e.g., /mnt/storage)"
    echo ""
    
    local files_dir="./files"
    local data_dir="./data"
    local config_dir="./config"  # Always use repo config dir
    local workspace_dir="/mnt/workspace"
    local ssh_key_dir="\${CONFIG_BASE_DIR}/ssh"
    
    if prompt_yes_no "Customize storage paths?" "n"; then
        files_dir=$(prompt_input "User files directory" "./files")
        data_dir=$(prompt_input "Application data directory" "./data")
        
        echo ""
        echo "Coder workspace directory (must be absolute path):"
        workspace_dir=$(prompt_input "Workspace directory" "/mnt/workspace")
        
        while [[ ! "$workspace_dir" =~ ^/ ]]; do
            log_error "Workspace directory must be an absolute path (start with /)"
            workspace_dir=$(prompt_input "Workspace directory" "/mnt/workspace")
        done
    fi
    
    log_success "Storage paths configured"
    
    # ========================================================================
    # STEP 5: Review & Generate
    # ========================================================================
    clear
    show_progress $total_steps $total_steps "Review & Generate Configuration"
    
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
    echo "  Base:             ${selected_profiles[*]}"
    if $has_dev && [[ "$git_service" != "none" ]]; then
        echo "  Git:              $git_service"
    fi
    if $has_ai; then
        if [[ ${#ai_frontends[@]} -gt 0 ]]; then
            echo "  AI frontends:     ${ai_frontends[*]}"
        else
            echo "  AI frontends:     none (Ollama API only)"
        fi
        if $use_gpu; then
            echo "  GPU:              enabled (nvidia)"
        fi
    fi
    if $has_personal && [[ ${#personal_services[@]} -gt 0 ]]; then
        echo "  Personal:         ${personal_services[*]}"
    fi
    if $has_automation && [[ ${#automation_services[@]} -gt 0 ]]; then
        echo "  Automation:       ${automation_services[*]}"
    fi
    echo ""
    
    if ! prompt_yes_no "Generate .env file with these settings?" "y"; then
        log_error "Configuration cancelled by user"
        return 1
    fi
    
    # ========================================================================
    # Generate .env file
    # ========================================================================
    log_step "Assembling modular env template for selected profiles..."
    
    # Generate .env directly from modular templates
    local env_templates_dir="${SCRIPT_DIR}/tools/env/templates"
    if [[ -d "$env_templates_dir" ]]; then
        # Use modular templates - assemble directly to .env
        local profiles_csv=$(IFS=, ; echo "${selected_profiles[*]}")
        log_info "Generating .env from modular templates for profiles: $profiles_csv"
        
        # Assemble templates to temporary file
        local temp_template="${SCRIPT_DIR}/.env.tmp"
        if ! "${SCRIPT_DIR}/tools/env/scripts/assemble-env.sh" \
            --profiles "$profiles_csv" \
            --output "$temp_template" >/dev/null 2>&1; then
            log_error "Failed to assemble modular env template"
            rm -f "$temp_template"
            return 1
        fi
        
        # Generate .env from assembled template with secrets
        if ! "${SCRIPT_DIR}/tools/env-template-gen.sh" "$temp_template" "$env_file" >/dev/null 2>&1; then
            log_error "Failed to generate .env from template"
            rm -f "$temp_template"
            return 1
        fi
        
        # Clean up temp file
        rm -f "$temp_template"
    else
        # Modular templates are required
        log_error "Modular templates not found at: $env_templates_dir"
        log_error "Please ensure tools/env/templates/ directory exists"
        return 1
    fi
    
    # Step 3: Apply all collected configuration using safe update function
    log_step "Applying configuration values..."
    
    update_env_var "COMPUTER_NAME" "$computer_name" "$env_file"
    update_env_var "HOST_IP" "$host_ip" "$env_file"
    update_env_var "TZ" "$timezone" "$env_file"
    update_env_var "PUID" "$puid" "$env_file"
    update_env_var "PGID" "$pgid" "$env_file"
    update_env_var "LAB_DOMAIN" "$lab_domain" "$env_file"
    update_env_var "BASE_DOMAIN" "$base_domain" "$env_file"
    
    # Set Cloudflare API token if provided
    if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        update_env_var "CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_API_TOKEN" "$env_file"
    fi
    
    update_env_var "DEFAULT_ADMIN_USER" "$admin_user" "$env_file"
    update_env_var "DEFAULT_ADMIN_EMAIL" "$admin_email" "$env_file"
    
    # Only set custom password if provided
    if [[ -n "$admin_password" ]]; then
        update_env_var "DEFAULT_ADMIN_PASSWORD" "$admin_password" "$env_file"
    fi
    
    # Set storage paths
    update_env_var "FILES_BASE_DIR" "$files_dir" "$env_file"
    update_env_var "DATA_BASE_DIR" "$data_dir" "$env_file"
    # Note: CONFIG_BASE_DIR not set in .env - compose files use ../config defaults
    # to ensure correct path resolution regardless of compose file location
    update_env_var "WORKSPACE_DIR" "$workspace_dir" "$env_file"
    update_env_var "SSH_KEY_DIR" "$ssh_key_dir" "$env_file"
    
    # Set git service selection (for dev profile)
    if $has_dev; then
        update_env_var "GIT_SERVICE" "$git_service" "$env_file"
    fi
    
    # Set registry cache configuration
    # The registry cache is used during setup to optimize Docker image pulls
    # and bypass Docker Hub rate limits. It starts automatically during setup.
    update_env_var "REGISTRY_DATA_DIR" "${data_dir}/registry-cache" "$env_file"
    update_env_var "REGISTRY_PORT" "5000" "$env_file"
    update_env_var "REGISTRY_MEMORY_LIMIT" "256m" "$env_file"
    
    # Add setup metadata
    add_setup_metadata "$env_file" "${selected_profiles[@]}"
    
    # Step 4: Build final profile list (base + sub-profiles) and write to .env
    log_step "Generating compose profile list..."
    local profiles_csv=$(IFS=, ; echo "${selected_profiles[*]}")
    
    # Append sub-profile choices (git service, AI frontends, personal, automation)
    if $has_dev && [[ "$git_service" != "none" ]]; then
        profiles_csv="${profiles_csv},${git_service}"
    fi
    if $has_ai && [[ ${#ai_frontends[@]} -gt 0 ]]; then
        for fe in "${ai_frontends[@]}"; do
            profiles_csv="${profiles_csv},${fe}"
        done
    fi
    if $has_ai && $use_gpu; then
        profiles_csv="${profiles_csv},gpu"
    fi
    if $has_personal && [[ ${#personal_services[@]} -gt 0 ]]; then
        for svc in "${personal_services[@]}"; do
            profiles_csv="${profiles_csv},${svc}"
        done
    fi
    if $has_automation && [[ ${#automation_services[@]} -gt 0 ]]; then
        for svc in "${automation_services[@]}"; do
            profiles_csv="${profiles_csv},${svc}"
        done
    fi
    
    # Write the full expanded profile list to COMPOSE_PROFILES in .env so that
    # start_services_with_profiles can read it back (avoiding the in-memory
    # selected_profiles array which only has the base profiles).
    if grep -q "^COMPOSE_PROFILES=" "$env_file"; then
        update_env_var "COMPOSE_PROFILES" "$profiles_csv" "$env_file"
    else
        echo "" >> "$env_file"
        echo "COMPOSE_PROFILES=$profiles_csv" >> "$env_file"
    fi
    update_env_var "SELECTED_PROFILES" "$profiles_csv" "$env_file"
    
    # Step 5: Generate custom docker-compose profile
    log_step "Generating custom docker-compose profile..."
    if "${SCRIPT_DIR}/tools/env/scripts/generate-custom-profile.sh" \
        --profiles "$profiles_csv" >/dev/null 2>&1; then
        log_success "Custom profile generated"
    else
        log_warn "Custom profile generation failed (will fall back to manual --profile flags)"
    fi
    
    log_success ".env file created successfully!"
    echo ""
    log_info "Final configuration saved to: .env"
    log_info "(Assembled from modular templates based on selected profiles)"
    
    # Show generated admin password if it was auto-generated
    if [[ -z "$admin_password" ]]; then
        local generated_password=$(grep "^DEFAULT_ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
        echo ""
        log_warn "IMPORTANT - Save this auto-generated admin password:"
        echo ""
        echo -e "${BOLD}  Username: $admin_user${NC}"
        echo -e "${BOLD}  Password: $generated_password${NC}"
        echo ""
        log_warn "Change this password after your first login to each service!"
    fi
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
SETUP_DATE="$timestamp"
SELECTED_PROFILES="$profiles_string"
EOF
    else
        update_env_var "SETUP_COMPLETED" "true" "$env_file"
        update_env_var "SETUP_DATE" "\"$timestamp\"" "$env_file"
        update_env_var "SELECTED_PROFILES" "\"$profiles_string\"" "$env_file"
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
    
    # Assemble modular template if available
    log_step "Assembling modular env template..."
    local env_templates_dir="${SCRIPT_DIR}/tools/env/templates"
    if [[ -d "$env_templates_dir" ]]; then
        # Use modular templates - assemble to temporary file
        local profiles_csv=$(IFS=, ; echo "${selected_profiles[*]}")
        log_info "Creating template for profiles: $profiles_csv"
        
        local temp_template="${SCRIPT_DIR}/.env.tmp"
        if ! "${SCRIPT_DIR}/tools/env/scripts/assemble-env.sh" \
            --profiles "$profiles_csv" \
            --output "$temp_template" >/dev/null 2>&1; then
            log_error "Failed to assemble modular env template"
            return 1
        fi
        
        # Generate from temporary template
        log_step "Generating .env with defaults..."
        if ! "${SCRIPT_DIR}/tools/env-template-gen.sh" "$temp_template" "$env_file" >/dev/null 2>&1; then
            log_error "Failed to generate .env from template"
            rm -f "$temp_template"
            return 1
        fi
        rm -f "$temp_template"
    else
        # Modular templates are required
        log_error "Modular templates not found at: $env_templates_dir"
        log_error "Please ensure tools/env/templates/ directory exists"
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
    
    # Add metadata
    add_setup_metadata "$env_file" "${selected_profiles[@]}"
    
    # Generate custom docker-compose profile
    log_step "Generating custom docker-compose profile..."
    if "${SCRIPT_DIR}/tools/env/scripts/generate-custom-profile.sh" \
        --profiles "$profiles_string" >/dev/null 2>&1; then
        log_success "Custom profile generated"
    else
        log_warn "Custom profile generation failed (will fall back to manual --profile flags)"
        # Fallback to original profile list if custom generation fails
        update_env_var "COMPOSE_PROFILES" "$profiles_string" "$env_file"
    fi
    
    log_success "Quick environment setup complete"
    log_info "Computer: $hostname"
    log_info "Host IP: $detected_ip"
    log_info "Profiles: $profiles_string"
}

# Export functions
export -f generate_env_interactive generate_env_quick
export -f add_setup_metadata show_progress update_env_profiles_only update_env_var
