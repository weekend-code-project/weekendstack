#!/bin/bash
# Profile and service selection for WeekendStack
# Allows users to choose which services to deploy

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Profile definitions — networking is no longer a user-visible option;
# Traefik/Pi-hole/Tunnel sub-profiles are auto-added by setup based on
# the Access Configuration wizard answers.
declare -A PROFILES=(
    ["all"]="Everything"
    ["core"]="Dashboard & speedtest"
    ["monitoring"]="Uptime & update monitoring"
    ["productivity"]="Business & productivity apps"
    ["dev"]="Development tools"
    ["ai"]="AI & LLM services"
    ["media"]="Media management"
)

# RAM requirements per profile (approximate, for display only)
declare -A PROFILE_RAM=(
    ["all"]="32GB+"
    ["core"]="~1GB"
    ["monitoring"]="~1GB"
    ["productivity"]="~12GB"
    ["dev"]="~5GB"
    ["ai"]="~9GB"
    ["media"]="~7GB"
)

# Core profile is always included (required for basic functionality)
CORE_REQUIRED=true

# Profile order for display (core is always installed, not shown as option)
# Note: networking/traefik/pihole/external are auto-derived — not listed here
PROFILE_ORDER=("monitoring" "productivity" "dev" "ai" "media" "all")

show_profile_matrix() {
    log_header "Available Service Profiles"
    
    printf "%-15s %s\n" "PROFILE" "DESCRIPTION"
    printf "%-15s %s\n" "-------" "-----------"
    
    for profile in "${PROFILE_ORDER[@]}"; do
        if [[ "$profile" == "core" ]]; then
            printf "%-15s %s (always included)\n" "$profile" "${PROFILES[$profile]}"
        else
            printf "%-15s %s\n" "$profile" "${PROFILES[$profile]}"
        fi
    done
    
    echo ""
    echo "Note: Core profile is always included (required for basic functionality)"
    echo "      'all' profile includes everything"
    echo ""
}

# Detect existing profile selection from .env file
detect_existing_profiles() {
    if [[ -f "$SCRIPT_DIR/.env" ]] && grep -q "^SELECTED_PROFILES=" "$SCRIPT_DIR/.env"; then
        grep "^SELECTED_PROFILES=" "$SCRIPT_DIR/.env" | cut -d'=' -f2 | tr -d '"'
    fi
}

# Prompt user to add to existing profiles or replace
prompt_layer_mode() {
    local existing_profiles="$1"
    
    # Clean up profile list: remove duplicates and core (since it's default)
    local -a profile_array=(${existing_profiles//,/ })
    local -a cleaned_profiles=()
    declare -A seen
    
    for prof in "${profile_array[@]}"; do
        if [[ "$prof" != "core" && -z "${seen[$prof]}" ]]; then
            seen[$prof]=1
            cleaned_profiles+=("$prof")
        fi
    done
    
    local display_profiles="${cleaned_profiles[*]}"
    display_profiles="${display_profiles// /, }"
    
    # Check if Coder is running
    local coder_running=false
    if docker ps --filter "name=^coder$" --format "{{.Names}}" 2>/dev/null | grep -q "^coder$"; then
        coder_running=true
    fi
    
    {
        echo ""
        if [[ -n "$display_profiles" ]]; then
            log_info "Current profiles: $display_profiles (+ core)"
        else
            log_info "Current profiles: core only"
        fi
        echo ""
        echo "Setup mode:"
        echo "  1) Add to existing profiles (layer on more services)"
        echo "  2) Replace with new selection"
        if [[ "$coder_running" == "true" ]]; then
            echo "  3) Just update Coder templates (skip full setup)"
        fi
        echo ""
    } >&2
    
    local valid_choices="1 or 2"
    if [[ "$coder_running" == "true" ]]; then
        valid_choices="1, 2, or 3"
    fi
    
    while true; do
        read -p "Choose mode ($valid_choices): " -r mode_choice </dev/tty
        if [[ "$mode_choice" == "1" ]]; then
            echo "add"
            return
        elif [[ "$mode_choice" == "2" ]]; then
            echo "replace"
            return
        elif [[ "$mode_choice" == "3" && "$coder_running" == "true" ]]; then
            echo "templates-only"
            return
        else
            echo "Invalid choice. Please enter $valid_choices." >&2
        fi
    done
}

# Merge profiles (deduplicate)
merge_profiles() {
    local -a all_profiles=("$@")
    
    # Use associative array to deduplicate
    declare -A seen
    local -a unique=()
    
    for profile in "${all_profiles[@]}"; do
        if [[ -z "${seen[$profile]}" ]]; then
            seen[$profile]=1
            unique+=("$profile")
        fi
    done
    
    echo "${unique[@]}"
}

select_profiles_interactive() {
    # Check for existing profiles
    local existing_profiles_str=$(detect_existing_profiles)
    local layer_mode="replace"
    local -a existing_profiles=()
    
    if [[ -n "$existing_profiles_str" ]]; then
        # Convert comma-separated string to array and deduplicate
        IFS=',' read -ra existing_profiles <<< "$existing_profiles_str"
        
        # Deduplicate existing profiles
        local -a deduped=()
        declare -A seen
        for prof in "${existing_profiles[@]}"; do
            if [[ -z "${seen[$prof]}" ]]; then
                seen[$prof]=1
                deduped+=("$prof")
            fi
        done
        existing_profiles=("${deduped[@]}")
        
        # Reconstruct string for display
        existing_profiles_str="${existing_profiles[*]}"
        existing_profiles_str="${existing_profiles_str// /,}"
        
        layer_mode=$(prompt_layer_mode "$existing_profiles_str")
        
        # Handle templates-only mode
        if [[ "$layer_mode" == "templates-only" ]]; then
            echo "TEMPLATES_ONLY_MODE"
            return 0
        fi
    fi
    
    # Display to stderr so it shows on terminal (stdout is captured by command substitution)
    {
        log_header "Service Profile Selection"
        
        if [[ "$layer_mode" == "add" ]]; then
            echo "Current profiles: ${existing_profiles[*]}"
            echo "Select additional profiles to add:"
        else
            echo "Available deployment profiles:"
        fi
        echo ""
            echo "Note: Core profile (Glance, Speedtest) is always installed"
        echo "      Networking (Traefik/Pi-hole/Tunnel) is configured via the Access wizard"
        echo ""
        for i in $(seq 1 ${#PROFILE_ORDER[@]}); do
            local profile="${PROFILE_ORDER[$((i-1))]}"
            local ram_hint="${PROFILE_RAM[$profile]:-}"
            if [[ -n "$ram_hint" ]]; then
                printf "  %d) %-14s - %-34s (%s)\n" "$i" "$profile" "${PROFILES[$profile]}" "$ram_hint"
            else
                printf "  %d) %-12s - %s\n" "$i" "$profile" "${PROFILES[$profile]}"
            fi
        done
        echo ""
        echo "Enter profile numbers (space-separated) or press Enter for 'all':"
        echo "Example: '1 4' for monitoring + dev"
        echo ""
    } >&2
    
    read -p "Selection: " -r user_input </dev/tty
    
    local selected_indices
    if [[ -z "$user_input" ]]; then
        selected_indices="${#PROFILE_ORDER[@]}"  # Default to 'all' which is the last option
        {
            log_info "No selection made, defaulting to 'all' profiles"
        } >&2
    else
        selected_indices="$user_input"
    fi
    
    local -a new_profiles=()
    for idx in $selected_indices; do
        # Skip if idx is not a number or out of range
        if [[ "$idx" =~ ^[0-9]+$ ]] && [[ $idx -ge 1 ]] && [[ $idx -le ${#PROFILE_ORDER[@]} ]]; then
            # Convert 1-based index to 0-based array index
            new_profiles+=("${PROFILE_ORDER[$((idx-1))]}")
        fi
    done
    
    if [[ ${#new_profiles[@]} -eq 0 ]]; then
        {
            log_warn "No valid profiles selected, defaulting to 'all'"
        } >&2
        new_profiles=("all")
    fi
    
    # Always include core profile (unless 'all' is selected, which includes everything)
    if [[ ! " ${new_profiles[*]} " =~ " all " ]] && [[ ! " ${new_profiles[*]} " =~ " core " ]]; then
        new_profiles=("core" "${new_profiles[@]}")
    fi
    
    # Merge with existing if in add mode
    local -a final_profiles=()
    if [[ "$layer_mode" == "add" ]]; then
        final_profiles=($(merge_profiles "${existing_profiles[@]}" "${new_profiles[@]}"))
    else
        final_profiles=("${new_profiles[@]}")
    fi
    
    {
        echo ""
        if [[ "$layer_mode" == "add" ]]; then
            log_success "Combined profiles: ${final_profiles[*]}"
        else
            log_success "Selected profiles: ${final_profiles[*]}"
        fi

        # Warn if AI profile is selected but system RAM is below 16GB
        local _has_ai_in_final=false
        for _fp in "${final_profiles[@]}"; do
            if [[ "$_fp" == "ai" || "$_fp" == "all" ]]; then
                _has_ai_in_final=true
                break
            fi
        done
        local _total_mem
        _total_mem=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
        _total_mem="${_total_mem:-999}"
        if $_has_ai_in_final && (( _total_mem < 16 )); then
            echo ""
            echo -e "\033[1;33m  ⚠ WARNING: AI profile selected but only ${_total_mem}GB RAM detected.\033[0m"
            echo "  Ollama and AI model inference work best with 16GB or more."
            echo "  On ${_total_mem}GB you can run small models (e.g. qwen2.5:0.5b, gemma:2b)."
            echo "  Large models (7B+) will be very slow or fail to load."
            echo ""
            read -p "  Continue with AI profile anyway? [y/N]: " -r _ai_warn_yn </dev/tty
            if [[ ! "$_ai_warn_yn" =~ ^[Yy]$ ]]; then
                echo "Installation cancelled. Re-run setup and choose profiles without AI." >&2
                exit 0
            fi
        fi
        echo ""
    } >&2
    
    # Echo to stdout for capture by calling script
    echo "${final_profiles[@]}"
}

select_profiles_quick() {
    # All display goes to stderr so stdout is clean for capture by the caller
    {
        log_header "Quick Profile Selection"

        echo "Available quick deployment options:"
        echo "  1) Foundation    - Core only (recommended starter)"
        echo "  2) Developer     - Core + Dev + AI services"
        echo "  3) Productivity  - Core + Productivity + Media"
        echo "  4) Complete      - All services"
        echo "  5) Custom        - Choose specific profiles"
        echo "  (Cloudflare Tunnel, local domain, and Pi-hole are configured in the Access wizard)"
        echo ""
    } >&2

    local choice
    # In quick mode, DRY_RUN mode, or if stdin is not a terminal, use default Foundation
    if [[ "${SETUP_MODE:-interactive}" == "quick" ]] || [[ "${DRY_RUN:-false}" == "true" ]] || ! [[ -t 0 ]]; then
        log_info "Using default Foundation setup (core only)"
        choice=0
    else
        choice=$(prompt_select "Select deployment type:" "Foundation" "Developer" "Productivity" "Complete" "Custom")
    fi

    local selected_profiles=()

    case $choice in
        0) # Foundation
            selected_profiles=("core")
            ;;
        1) # Developer
            selected_profiles=("core" "dev" "ai")
            ;;
        2) # Productivity
            selected_profiles=("core" "productivity" "media")
            ;;
        3) # Complete
            selected_profiles=("all")
            ;;
        4) # Custom
            selected_profiles=($(select_profiles_interactive))
            ;;
    esac

    log_success "Selected profiles: ${selected_profiles[*]}" >&2
    echo "${selected_profiles[@]}"
}

get_services_for_profiles() {
    local profiles=("$@")
    local compose_dir="${SCRIPT_DIR}/.."
    local services=()
    
    # If 'all' is selected, return all profiles
    if [[ " ${profiles[*]} " =~ " all " ]]; then
        echo "all"
        return 0
    fi
    
    # Parse docker-compose files for services in selected profiles
    for profile in "${profiles[@]}"; do
        case "$profile" in
            core)
                services+=("glance" "vaultwarden")
                ;;
            networking)
                services+=("traefik" "link-router" "cert-generator" "error-pages")
                ;;
            pihole)
                services+=("pihole" "pihole-dnsmasq-init")
                ;;
            external)
                services+=("cloudflare-tunnel")
                ;;
            ai)
                services+=("ollama" "open-webui" "searxng" "anythingllm" "librechat" "localai" "stable-diffusion" "diffrhythm")  # note: localai is an opt-in sub-profile now
                ;;
            dev)
                services+=("coder" "gitea" "guacamole" "registry")
                ;;
            productivity)
                services+=("nocodb" "n8n" "paperless-ngx" "activepieces" "postiz" "docmost" "focalboard" "trilium" "vikunja" "it-tools" "excalidraw" "filebrowser" "hoarder" "bytestash" "resourcespace")
                ;;
            media)
                services+=("kavita" "navidrome")
                ;;
            monitoring)
                services+=("wud" "uptime-kuma")
                ;;
        esac
    done
    
    # Remove duplicates
    local unique_services=($(echo "${services[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    echo "${unique_services[@]}"
}

estimate_resources() {
    local profiles=("$@")
    local estimated_memory=2 # Base overhead (GB)
    local estimated_disk=10  # Base requirements (GB)
    
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all)
                estimated_memory=48
                estimated_disk=100
                return
                ;;
            core)
                estimated_memory=$((estimated_memory + 1))
                estimated_disk=$((estimated_disk + 5))
                ;;
            networking|pihole)
                estimated_memory=$((estimated_memory + 2))
                estimated_disk=$((estimated_disk + 5))
                ;;
            ai)
                estimated_memory=$((estimated_memory + 16))
                estimated_disk=$((estimated_disk + 40))
                ;;
            dev)
                estimated_memory=$((estimated_memory + 8))
                estimated_disk=$((estimated_disk + 20))
                ;;
            productivity)
                estimated_memory=$((estimated_memory + 2))
                estimated_disk=$((estimated_disk + 10))
                ;;
            monitoring)
                estimated_memory=$((estimated_memory + 4))
                estimated_disk=$((estimated_disk + 10))
                ;;
        esac
    done
    
    echo "$estimated_memory $estimated_disk"
}

check_system_resources() {
    local required_memory=$1
    local required_disk=$2
    
    log_step "Checking system resources..."
    
    # Check available memory (in GB)
    local available_memory
    if check_command free; then
        available_memory=$(free -g | awk '/^Mem:/{print $2}')
    else
        log_warn "Cannot determine available memory"
        available_memory=999
    fi
    
    # Check available disk space (in GB)
    local available_disk
    available_disk=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    
    echo ""
    echo "System resources:"
    echo "  Memory: ${available_memory}GB available (${required_memory}GB required)"
    echo "  Disk:   ${available_disk}GB available (${required_disk}GB required)"
    echo ""
    
    local warnings=0
    
    if ((available_memory < required_memory)); then
        log_warn "Insufficient memory: ${available_memory}GB < ${required_memory}GB"
        warnings=$((warnings + 1))
    else
        log_success "Memory check passed"
    fi
    
    if ((available_disk < required_disk)); then
        log_warn "Insufficient disk space: ${available_disk}GB < ${required_disk}GB"
        warnings=$((warnings + 1))
    else
        log_success "Disk space check passed"
    fi
    
    if ((warnings > 0)); then
        echo ""
        if ! prompt_yes_no "Continue anyway?" "n"; then
            return 1
        fi
        clear
    fi
    
    return 0
}

# Export functions
export -f show_profile_matrix select_profiles_interactive select_profiles_quick
export -f detect_existing_profiles prompt_layer_mode merge_profiles
export -f get_services_for_profiles estimate_resources check_system_resources
