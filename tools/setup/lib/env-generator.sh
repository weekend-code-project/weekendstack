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
    # If the key does not exist in the file, append it.
    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        awk -v var="$var_name" -v val="$var_value" '
            $0 ~ "^" var "=" { print var "=" val; next }
            { print }
        ' "$env_file" > "${env_file}.tmp" && mv "${env_file}.tmp" "$env_file"
    else
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

# Progress tracking
show_progress() {
    local current=$1
    local total=$2
    local section=$3
    screen_title "Configuration Step $current of $total" "$section"
}

# Update profiles in existing .env without reconfiguring
update_env_profiles_only() {
    local env_file="${SCRIPT_DIR}/.env"
    local selected_profiles=("$@")
    
    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found - running full configuration"
        return 1
    fi
    
    screen_title "Service Profiles" "Update the active service set while keeping the rest of the current .env unchanged."
    
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    
    log_step "Updating COMPOSE_PROFILES to: $profiles_string"
    update_env_var "COMPOSE_PROFILES" "$profiles_string" "$env_file"
    
    # Update metadata
    local timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    update_env_var "SETUP_DATE" "$timestamp" "$env_file"
    update_env_var "SELECTED_PROFILES" "$profiles_string" "$env_file"
    
    log_success "Profile update complete"
    
    return 0
}

generate_env_interactive() {
    local env_file="${SCRIPT_DIR}/.env"
    local selected_profiles=("$@")
    local has_dev=false
    local has_ai=false

    for profile in "${selected_profiles[@]}"; do
        if [[ "$profile" == "dev" ]] || [[ "$profile" == "all" ]]; then
            has_dev=true
        fi
        if [[ "$profile" == "ai" ]] || [[ "$profile" == "all" ]]; then
            has_ai=true
        fi
    done

    local total_steps=4  # System Settings + Access Configuration + Admin Credentials + File Storage
    if $has_dev; then
        ((total_steps++))
    fi
    if $has_ai; then
        ((total_steps++))
    fi
    
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
        clear_screen
    fi
    
    # Backup existing .env if it exists
    if [[ -f "$env_file" ]]; then
        screen_title "Existing Configuration" "A .env file is already present for this stack."
        log_warn "Existing .env file found"
        if prompt_yes_no "Create backup before generating new .env?" "y"; then
            backup_file "$env_file"
        fi
    fi
    
    # ========================================================================
    # STEP 1: System Settings
    # ========================================================================
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
    
    local lab_domain=""
    local base_domain="localhost"
    local domain_mode="ip"
    local local_dns_mode="none"
    local use_pihole=false
    local _step=1  # running step counter
    
    # ========================================================================
    # STEP: Access Configuration (always shown — determines networking stack)
    # ========================================================================
    _step=$((_step + 1))
    show_progress $_step $total_steps "Access Configuration"
    
    echo -e "${BOLD}How should you access WeekendStack?${NC}"
    echo "  1) Tunnel       - Public HTTPS URLs through Cloudflare Tunnel"
    echo "  2) Local Domain - Friendly local HTTPS URLs like https://service.lab"
    echo "  3) Local IP     - Direct http://${host_ip}:PORT access (no DNS)"
    echo ""

    local access_choice
    access_choice=$(prompt_number_choice "Select" "2" "1" "3")
    echo ""

    case "$access_choice" in
        1)
            domain_mode="tunnel"
            base_domain="localhost"
            lab_domain=""
            use_pihole=false
            local_dns_mode="none"
            log_info "Tunnel access selected — Cloudflare domain and token setup come later."
            ;;
        2)
            domain_mode="local"

            read -r -p "  Local domain suffix [lab]: " lab_domain_input </dev/tty
            lab_domain_input="${lab_domain_input// /}"
            lab_domain="${lab_domain_input:-lab}"
            log_success "Local domain set: .${lab_domain}"

            echo ""
            echo -e "${BOLD}DNS for local domain?${NC}"
            echo "  1) Install Pi-hole  — handles DNS + optional ad blocking (recommended)"
            echo "  2) Use my existing DNS/router"
            local _dns_choice
            _dns_choice=$(prompt_number_choice "Select" "1" "1" "2")
            echo ""

            if [[ "$_dns_choice" == "2" ]]; then
                use_pihole=false
                local_dns_mode="manual"
                log_info "Manual DNS selected — add a wildcard record for *.${lab_domain} → ${host_ip}"
            else
                use_pihole=true
                local_dns_mode="pihole"
                log_success "Pi-hole will be installed for local DNS"
            fi
            ;;
        3|*)
            domain_mode="ip"
            base_domain="localhost"
            lab_domain=""
            use_pihole=false
            local_dns_mode="none"
            log_info "IP access selected — services will use ${host_ip}:PORT"
            ;;
    esac

    echo ""
    case "$(normalize_access_mode "$domain_mode")" in
        tunnel)
            log_success "Access mode: Tunnel"
            ;;
        local)
            if [[ "$local_dns_mode" == "pihole" ]]; then
                log_success "Access mode: Local domain (.${lab_domain} via Pi-hole)"
            else
                log_success "Access mode: Local domain (.${lab_domain} via your existing DNS/router)"
            fi
            ;;
        ip)
            log_info "Access mode: Local IP"
            ;;
    esac
    
    log_success "Access configuration complete"
    
    # ========================================================================
    # STEP: Git Service Selection (only if dev profile selected)
    # ========================================================================
    local git_service="none"
    
    if $has_dev; then
        _step=$((_step + 1))
        show_progress $_step $total_steps "Git Service Selection"
        
        echo "You selected the development profile which includes git hosting."
        echo ""
        echo "Select which git service to install:"
        echo ""
        echo "  1) None   - Skip git service (Coder IDE only)"
        echo "  2) Gitea  - Lightweight, fast self-hosted git (recommended)"

        local git_choice
        git_choice=$(prompt_number_choice "Select" "2" "1" "2")
        
        case "$git_choice" in
            1)
                git_service="none"
                log_info "Git service disabled"
                ;;
            2|*)
                git_service="gitea"
                log_success "Gitea selected (lightweight git hosting)"
                ;;
        esac
        
        log_success "Git service configuration complete"
    fi
    
    # ========================================================================
    # STEP: AI Chat Frontend Selection (only if ai profile selected)
    # ========================================================================
    local -a ai_frontends=()
    local -a ai_extra_services=()
    local -a ai_gpu_services=()
    local use_gpu=false

    if $has_ai; then
        _step=$((_step + 1))
        show_progress $_step $total_steps "AI Services Configuration"

        # ── RAM warning ────────────────────────────────────────────────────
        local _ai_total_mem
        _ai_total_mem=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
        _ai_total_mem="${_ai_total_mem:-${TOTAL_MEMORY_GB:-999}}"
        if (( _ai_total_mem < 16 )); then
            echo ""
            echo -e "\033[1;33m  ⚠ WARNING: Only ${_ai_total_mem}GB RAM detected.\033[0m"
            echo "  AI services (Ollama + models) work best with 16GB or more."
            echo "  With ${_ai_total_mem}GB you can run small models (e.g. qwen2.5:0.5b, gemma:2b)."
            echo "  Large models (7B+) will be very slow or may fail to load."
            echo ""
        fi

        # ── GPU detection ────────────────────────────────────────────────
        if [[ "${GPU_AVAILABLE:-false}" == "true" ]]; then
            log_success "NVIDIA GPU detected — GPU-accelerated inference is available"
            use_gpu=false  # confirmed below when user picks GPU services
        else
            log_info "No GPU detected — Ollama will run on CPU (slower inference)"
        fi
        echo ""

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # Part 1 — Chat Frontend
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        screen_section "Chat Frontend" "Ollama (LLM backend, ~4GB RAM) is always installed."
        echo "Select which chat UI(s) to add (space-separated for multiple, e.g. '2 3'):"
        echo ""
        echo "  1) None        - No chat UI (Ollama API only)"
        echo "  2) Open WebUI  - Clean, polished UI for local models   (~2GB RAM)  [recommended]"
        echo "  3) LibreChat   - Multi-provider: OpenAI, Anthropic, Ollama, and more (~1.5GB RAM)"
        echo "  4) AnythingLLM - Document Q&A with RAG and vector DB   (~2GB RAM)"
        echo ""

        local ai_frontend_input
        read -r -p "  Select [2]: " ai_frontend_input </dev/tty
        ai_frontend_input="${ai_frontend_input:-2}"

        if [[ "$ai_frontend_input" == "1" ]]; then
            ai_frontends=()
            log_info "No chat frontend selected — Ollama API only"
        else
            for n in $ai_frontend_input; do
                case "$n" in
                    1) ;;  # explicit none — ignore any trailing numbers
                    2) ai_frontends+=("open-webui") ;;
                    3) ai_frontends+=("librechat") ;;
                    4) ai_frontends+=("anythingllm") ;;
                    *) log_warn "Unknown frontend option: $n (skipped)" ;;
                esac
            done
            if [[ ${#ai_frontends[@]} -gt 0 ]]; then
                log_success "Selected AI frontend(s): ${ai_frontends[*]}"
            else
                log_info "No valid frontend selected — Ollama API only"
            fi
        fi

        screen_title "AI Services Configuration" "Optional AI Services"
        echo "Optional extras (space-separated for multiple, e.g. '2 3'):"
        echo "  1) None    - Skip optional extras"
        echo "  2) SearXNG - Privacy-focused search engine         (~1GB RAM)"
        echo "  3) Whisper - OpenAI Whisper speech-to-text API     (~4GB RAM)"
        echo "  4) LocalAI - OpenAI-compatible local API server    (~4GB RAM)"
        echo ""

        local ai_extra_input
        read -r -p "  Select [1]: " ai_extra_input </dev/tty
        ai_extra_input="${ai_extra_input:-1}"

        for n in $ai_extra_input; do
            case "$n" in
                1) ;;  # None — no extras
                2) ai_extra_services+=("searxng") ;;
                3) ai_extra_services+=("whisper") ;;
                4) ai_extra_services+=("localai") ;;
                *) log_warn "Unknown additional service option: $n (skipped)" ;;
            esac
        done
        if [[ ${#ai_extra_services[@]} -gt 0 ]]; then
            log_success "Additional AI services: ${ai_extra_services[*]}"
        fi

        echo ""

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # Part 3 — GPU-Accelerated Services (only if GPU detected)
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if [[ "${GPU_AVAILABLE:-false}" == "true" ]]; then
            screen_title "AI Services Configuration" "GPU-Accelerated Services"
            echo "Enable NVIDIA-backed workloads for faster inference and speech processing."
            echo ""
            echo "Your NVIDIA GPU can accelerate the following services:"
            echo ""
            echo "  1) None       - No GPU acceleration (use CPU Ollama)"
            echo "  2) GPU Ollama - GPU-accelerated LLM inference, recommended (~4GB VRAM)"
            echo "  3) WhisperX   - Advanced STT with speaker diarization      (~8GB VRAM)"
            echo "  4) PrivateGPT - Private offline document Q&A               (~4GB VRAM)"
            echo ""
            echo "Select numbers to enable, space-separated (e.g. '2 3'). Press Enter for None:"
            echo ""

            local ai_gpu_input
            read -r -p "  Select [1]: " ai_gpu_input </dev/tty
            ai_gpu_input="${ai_gpu_input:-1}"

            for n in $ai_gpu_input; do
                case "$n" in
                    1) ;;  # None — CPU Ollama only
                    2) ai_gpu_services+=("gpu-ollama")   ; use_gpu=true ;;
                    3) ai_gpu_services+=("whisperx")     ; use_gpu=true ;;
                    4) ai_gpu_services+=("privategpt")   ; use_gpu=true ;;
                    *) log_warn "Unknown GPU service option: $n (skipped)" ;;
                esac
            done
            if $use_gpu; then
                log_success "GPU profile enabled: ${ai_gpu_services[*]}"
            else
                log_info "No GPU services selected"
            fi
        else
            log_info "No GPU detected — GPU-accelerated services skipped"
        fi

        log_success "AI service configuration complete"
    fi
    
    # ========================================================================
    # STEP: Admin Credentials (always shown)
    # ========================================================================
    _step=$((_step + 1))
    show_progress $_step $total_steps "Default Admin Credentials"
    
    echo "Many services (Coder, Gitea, Open WebUI, Paperless, File Browser, etc.) support auto-provisioning"
    echo "with default credentials. These will be used during initial setup."
    echo ""
    log_warn "IMPORTANT: Change these after first login — they protect all your services!"
    echo ""
    
    local admin_user="admin"
    local admin_email="admin@example.com"
    local admin_password=""  # Will be auto-generated if left blank

    if prompt_yes_no "Customize admin credentials?" "y"; then
        echo ""
        admin_user=$(prompt_input "Admin username" "admin")

        echo ""
        while true; do
            admin_email=$(prompt_input "Admin email" "admin@example.com")
            if validate_email "$admin_email"; then
                break
            fi
            log_error "Invalid email address. Please enter a valid email."
        done

        echo ""
        while true; do
            admin_password=$(prompt_password "Admin password (leave blank to auto-generate a secure one)" "yes")

            if [[ -z "$admin_password" ]]; then
                break
            fi

            if [[ ${#admin_password} -lt 12 ]]; then
                log_error "Admin password must be at least 12 characters so all supported services can be bootstrapped automatically."
                continue
            fi

            break
        done

        if [[ -z "$admin_password" ]]; then
            echo ""
            log_info "Will use auto-generated random password (you'll see it in .env and SETUP_SUMMARY.md)"
        fi
    fi
    
    log_success "Admin credentials configured"
    
    # ========================================================================
    # STEP: File Storage Paths
    # ========================================================================
    _step=$((_step + 1))
    show_progress $_step $total_steps "File Storage Paths"
    
    echo "WeekendStack uses base directories for data storage:"
    echo ""
    echo "  1. FILES_BASE_DIR  - User content (documents, media, photos)"
    echo "  2. DATA_BASE_DIR   - Application databases and state"
    echo ""
    echo "Config files stay in ./config (part of repository)"
    echo ""
    echo "Default: Absolute paths under project directory"
    echo "Advanced: Can use absolute paths or NFS mounts (e.g., /mnt/storage)"
    echo ""
    
    local files_dir="${SCRIPT_DIR}/files"
    local data_dir="${SCRIPT_DIR}/data"
    local config_dir="${SCRIPT_DIR}/config"  # Always use repo config dir
    local workspace_dir="/mnt/workspace"
    local ssh_key_dir="\${CONFIG_BASE_DIR}/ssh"
    
    if prompt_yes_no "Customize storage paths?" "n"; then
        files_dir=$(prompt_input "User files directory" "${SCRIPT_DIR}/files")
        data_dir=$(prompt_input "Application data directory" "${SCRIPT_DIR}/data")
        
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
    show_progress $total_steps $total_steps "Review & Generate Configuration"
    
    echo "Configuration summary:"
    echo ""
    echo -e "${BOLD}System Settings:${NC}"
    echo "  Computer Name:    $computer_name"
    echo "  Host IP:          $host_ip"
    echo "  Timezone:         $timezone"
    echo "  User Permissions: UID=$puid GID=$pgid"
    echo ""
    echo -e "${BOLD}Access:${NC}"
    case "$(normalize_access_mode "$domain_mode")" in
        tunnel)
            echo "  Mode:             Tunnel"
            ;;
        local)
            echo "  Mode:             Local domain"
            ;;
        *)
            echo "  Mode:             Local IP"
            ;;
    esac
    if [[ -n "$lab_domain" ]]; then
        echo "  Local Domain:     .$lab_domain"
    else
        echo "  Local Domain:     none"
    fi
    if [[ "$(normalize_access_mode "$domain_mode")" == "local" ]]; then
        case "$local_dns_mode" in
            pihole) echo "  Local DNS:        Pi-hole" ;;
            manual) echo "  Local DNS:        Existing DNS/router" ;;
        esac
    fi
    if [[ "$(normalize_access_mode "$domain_mode")" == "tunnel" ]]; then
        echo "  External Domain:  (configured in Cloudflare wizard step)"
    else
        echo "  External Access:  disabled"
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
    echo "  Config:           ${SCRIPT_DIR}/config"
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
        if [[ ${#ai_extra_services[@]} -gt 0 ]]; then
            echo "  AI extras:        ${ai_extra_services[*]}"
        fi
        if $use_gpu; then
            echo "  GPU services:     ${ai_gpu_services[*]:-gpu}"
        fi
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
        # Build the full profile list including sub-profiles (git service, etc.)
        # so that sub-profile env templates (e.g. gitea.env.example) are included
        # and their secrets get auto-generated at template time.
        local profiles_csv=$(IFS=, ; echo "${selected_profiles[*]}")
        if $has_dev && [[ "$git_service" != "none" ]]; then
            profiles_csv="${profiles_csv},${git_service}"
        fi
        log_info "Generating .env from modular templates for profiles: $profiles_csv"

        # Assemble templates to temporary file
        local temp_template="${SCRIPT_DIR}/.env.tmp"
        "${SCRIPT_DIR}/tools/env/scripts/assemble-env.sh" \
            --profiles "$profiles_csv" \
            --output "$temp_template" 2>&1 | grep -v '\[INFO\]\|\[WARN\]\|\[SECTION\]\|\[SUCCESS\]'
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
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
    update_env_var "LAB_DOMAIN" "${lab_domain:-lab}" "$env_file"
    update_env_var "BASE_DOMAIN" "$base_domain" "$env_file"
    update_env_var "DOMAIN_MODE" "$domain_mode" "$env_file"
    
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

    # Explicitly propagate admin credentials to services that support deterministic
    # env-based seeding. Values come from the shared auth policy manifest so setup,
    # summary output, and runtime bootstrap stay in sync.
    auth_policy_apply_seed_env_defaults "$env_file"
    
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
        case "$(normalize_access_mode "$domain_mode")" in
            tunnel)
                update_env_var "CODER_ACCESS_URL" "https://coder.${base_domain}" "$env_file"
                ;;
            local)
                update_env_var "CODER_ACCESS_URL" "https://coder.${lab_domain}" "$env_file"
                ;;
            *)
                update_env_var "CODER_ACCESS_URL" "http://${host_ip}:7080" "$env_file"
                ;;
        esac
    fi

    # Set Docmost APP_URL to the external HTTPS URL when Cloudflare is configured
    # (Docmost uses APP_URL for CORS/collab-token validation; must match browser URL)
    if has_tunnel_access_mode "$domain_mode" && [[ "$base_domain" != "localhost" ]]; then
        update_env_var "DOCMOST_APP_URL" "https://docmost.${base_domain}" "$env_file"
    elif has_local_domain_access_mode "$domain_mode"; then
        update_env_var "DOCMOST_APP_URL" "https://docmost.${lab_domain}" "$env_file"
    fi

    # Set external-facing app URLs for services that depend on absolute callback/public URLs.
    # Postiz OAuth and NocoDB auth links must match the browser URL when exposed via Cloudflare.
    if has_tunnel_access_mode "$domain_mode"; then
        update_env_var "POSTIZ_MAIN_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "POSTIZ_FRONTEND_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "POSTIZ_NEXT_PUBLIC_BACKEND_URL" "https://postiz.${base_domain}/api" "$env_file"
        update_env_var "POSTIZ_NEXTAUTH_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "POSTIZ_BASE_URL" "https://postiz.${base_domain}" "$env_file"
        update_env_var "NOCODB_PUBLIC_URL" "https://nocodb.${base_domain}" "$env_file"
        # Speedtest APP_URL must match the public URL for correct redirects and login
        update_env_var "SPEEDTEST_APP_URL" "https://speedtest.${base_domain}" "$env_file"
    elif has_local_domain_access_mode "$domain_mode"; then
        update_env_var "POSTIZ_MAIN_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_FRONTEND_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_NEXT_PUBLIC_BACKEND_URL" "https://postiz.${lab_domain}/api" "$env_file"
        update_env_var "POSTIZ_NEXTAUTH_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "POSTIZ_BASE_URL" "https://postiz.${lab_domain}" "$env_file"
        update_env_var "NOCODB_PUBLIC_URL" "https://nocodb.${lab_domain}" "$env_file"
        update_env_var "SPEEDTEST_APP_URL" "https://speedtest.${lab_domain}" "$env_file"
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
    
    # Append sub-profile choices (git service, AI frontends, AI extras)
    if $has_dev && [[ "$git_service" != "none" ]]; then
        profiles_csv="${profiles_csv},${git_service}"
    fi
    if $has_ai && [[ ${#ai_frontends[@]} -gt 0 ]]; then
        for fe in "${ai_frontends[@]}"; do
            profiles_csv="${profiles_csv},${fe}"
        done
    fi
    if $has_ai && [[ ${#ai_extra_services[@]} -gt 0 ]]; then
        for es in "${ai_extra_services[@]}"; do
            profiles_csv="${profiles_csv},${es}"
        done
    fi
    if $has_ai; then
        if $use_gpu; then
            profiles_csv="${profiles_csv},gpu"
        else
            profiles_csv="${profiles_csv},ollama-cpu"
        fi
    fi
    
    # Auto-append access sub-profiles derived from the Access Configuration wizard.
    # These are never selected manually — they are driven entirely by the two questions.
    #   networking  = Traefik + Link-Router + Cert-Generator + Error-Pages
    #   pihole      = Pi-hole + pihole-dnsmasq-init
    #   external    = Cloudflare Tunnel container
    if [[ "$(normalize_access_mode "$domain_mode")" != "ip" ]]; then
        profiles_csv="${profiles_csv},networking"
    fi
    if $use_pihole; then
        profiles_csv="${profiles_csv},pihole"
    fi
    if has_tunnel_access_mode "$domain_mode"; then
        profiles_csv="${profiles_csv},external"
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
        echo ""
        pause_for_enter
    fi
}

add_setup_metadata() {
    local env_file="$1"
    shift
    local selected_profiles=("$@")
    
    # Add setup metadata to .env file
    local timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    local profiles_string="${selected_profiles[*]}"
    profiles_string="${profiles_string// /,}"
    
    # The assembled templates already define these keys, so key presence is the
    # reliable indicator. The old comment-based check duplicated metadata.
    if ! grep -q "^SETUP_COMPLETED=" "$env_file"; then
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
        "${SCRIPT_DIR}/tools/env/scripts/assemble-env.sh" \
            --profiles "$profiles_csv" \
            --output "$temp_template" 2>&1 | grep -v '\[INFO\]\|\[WARN\]\|\[SECTION\]\|\[SUCCESS\]'
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
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
    update_env_var "COMPOSE_PROFILES" "$profiles_string" "$env_file"
    update_env_var "SELECTED_PROFILES" "$profiles_string" "$env_file"
    
    # Generate the legacy custom docker-compose profile as an auxiliary artifact.
    # The active profile list now comes from COMPOSE_PROFILES, which avoids
    # service redefinition conflicts in Compose includes.
    log_step "Generating custom docker-compose profile..."
    if "${SCRIPT_DIR}/tools/env/scripts/generate-custom-profile.sh" \
        --profiles "$profiles_string" >/dev/null 2>&1; then
        log_success "Custom profile generated"
    else
        log_warn "Custom profile generation failed (continuing with COMPOSE_PROFILES=${profiles_string})"
    fi
    
    log_success "Quick environment setup complete"
    log_info "Computer: $hostname"
    log_info "Host IP: $detected_ip"
    log_info "Profiles: $profiles_string"
}

# Export functions
export -f generate_env_interactive generate_env_quick
export -f add_setup_metadata show_progress update_env_profiles_only update_env_var
