#!/bin/bash
# Profile and service selection for WeekendStack
# Allows users to choose which services to deploy

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Profile definitions (from profile-matrix.md)
declare -A PROFILES=(
    ["all"]="All services (everything including personal & automation)"
    ["core"]="Foundation (Glance, Link Router, Dozzle, Speedtest, Certs)"
    ["networking"]="Network infrastructure (Traefik, Pi-hole, Cloudflare)"
    ["monitoring"]="Full monitoring suite (Portainer, Uptime Kuma, Netdata)"
    ["productivity"]="Business apps (Vaultwarden, Paperless, NocoDB, N8N)"
    ["dev"]="Development tools (Coder, Gitea, GitLab)"
    ["ai"]="AI & LLM services (Ollama, Open WebUI, LocalAI)"
    ["media"]="Media management (Kavita, Navidrome, Immich)"
)

# Service counts per profile (approximate)
declare -A PROFILE_SERVICE_COUNTS=(
    ["all"]="65+"
    ["core"]="5"
    ["networking"]="5"
    ["monitoring"]="8"
    ["productivity"]="25"
    ["dev"]="8"
    ["ai"]="8-11"
    ["media"]="6"
)

# Profile order for display
PROFILE_ORDER=("all" "core" "networking" "monitoring" "productivity" "dev" "ai" "media")

show_profile_matrix() {
    log_header "Available Service Profiles"
    
    printf "%-15s %-10s %s\n" "PROFILE" "SERVICES" "DESCRIPTION"
    printf "%-15s %-10s %s\n" "-------" "--------" "-----------"
    
    for profile in "${PROFILE_ORDER[@]}"; do
        printf "%-15s %-10s %s\n" "$profile" "${PROFILE_SERVICE_COUNTS[$profile]}" "${PROFILES[$profile]}"
    done
    
    echo ""
    echo "Note: 'all' profile includes core, networking, and all other services"
    echo "      Multiple profiles can be selected for custom deployments"
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
    
    {
        echo ""
        log_info "Previous profile selection detected: $existing_profiles"
        echo ""
        echo "Setup mode:"
        echo "  1) Add to existing profiles (layer on more services)"
        echo "  2) Replace with new selection"
        echo ""
    } >&2
    
    while true; do
        read -p "Choose mode (1 or 2): " -r mode_choice </dev/tty
        if [[ "$mode_choice" == "1" ]]; then
            echo "add"
            return
        elif [[ "$mode_choice" == "2" ]]; then
            echo "replace"
            return
        else
            echo "Invalid choice. Please enter 1 or 2." >&2
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
        existing_profiles=($existing_profiles_str)
        layer_mode=$(prompt_layer_mode "$existing_profiles_str")
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
        printf "  %d) %-12s - %-8s %s\n" 0 "all" "${PROFILE_SERVICE_COUNTS[all]}" "${PROFILES[all]}"
        echo ""
        for i in $(seq 1 $((${#PROFILE_ORDER[@]} - 1))); do
            local profile="${PROFILE_ORDER[$i]}"
            printf "  %d) %-12s - %-8s %s\n" "$i" "$profile" "${PROFILE_SERVICE_COUNTS[$profile]}" "${PROFILES[$profile]}"
        done
        echo ""
        echo "Recommended starter: 1 2 (core + networking)"
        echo "Layer on more anytime by re-running setup."
        echo ""
        echo "Enter profile numbers (space-separated) or press Enter for 'all':"
        echo "Example: '1 2' for core + networking"
        echo ""
    } >&2
    
    read -p "Selection: " -r user_input </dev/tty
    
    local selected_indices
    if [[ -z "$user_input" ]]; then
        selected_indices="0"  # Default to 'all' which is index 0
        {
            log_info "No selection made, defaulting to 'all' profiles"
        } >&2
    else
        selected_indices="$user_input"
    fi
    
    local -a new_profiles=()
    for idx in $selected_indices; do
        # Skip if idx is not a number
        if [[ "$idx" =~ ^[0-9]+$ ]] && [[ $idx -lt ${#PROFILE_ORDER[@]} ]]; then
            new_profiles+=("${PROFILE_ORDER[$idx]}")
        fi
    done
    
    if [[ ${#new_profiles[@]} -eq 0 ]]; then
        {
            log_warn "No valid profiles selected, defaulting to 'all'"
        } >&2
        new_profiles=("all")
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
        echo ""
    } >&2
    
    # Echo to stdout for capture by calling script
    echo "${final_profiles[@]}"
}

select_profiles_quick() {
    log_header "Quick Profile Selection"
    
    echo "Available quick deployment options:"
    echo "  1) Foundation    - Core + Networking (recommended starter)"
    echo "  2) Developer     - Foundation + Dev + AI services"
    echo "  3) Productivity  - Foundation + Productivity + Media"
    echo "  4) Complete      - All services (includes personal & automation)"
    echo "  5) Custom        - Choose specific profiles"
    echo ""
    
    local choice
    # In DRY_RUN mode or if stdin is not a terminal, default to Foundation
    if [[ "${DRY_RUN:-false}" == "true" ]] || ! [[ -t 0 ]]; then
        log_info "Using default Foundation setup (core + networking)"
        choice=0
    else
        choice=$(prompt_select "Select deployment type:" "Foundation" "Developer" "Productivity" "Complete" "Custom")
    fi
    
    local selected_profiles=()
    
    case $choice in
        0) # Foundation
            selected_profiles=("core" "networking")
            ;;
        1) # Developer
            selected_profiles=("core" "networking" "dev" "ai")
            ;;
        2) # Productivity
            selected_profiles=("core" "networking" "productivity" "media")
            ;;
        3) # Complete
            selected_profiles=("all")
            ;;
        4) # Custom
            selected_profiles=($(select_profiles_interactive))
            ;;
    esac
    
    log_success "Selected profiles: ${selected_profiles[*]}"
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
                services+=("link-router" "glance" "vaultwarden")
                ;;
            networking)
                services+=("traefik" "pihole" "cert-generator" "pihole-dnsmasq-init" "error-pages")
                ;;
            ai)
                services+=("ollama" "open-webui" "searxng" "anythingllm" "librechat" "localai" "stable-diffusion" "diffrhythm")
                ;;
            dev)
                services+=("coder" "gitea" "gitlab" "guacamole" "registry")
                ;;
            productivity)
                services+=("nocodb" "n8n" "paperless-ngx" "activepieces" "postiz" "docmost" "focalboard" "trilium" "vikunja" "it-tools" "excalidraw" "filebrowser" "hoarder" "bytestash" "resourcespace")
                ;;
            personal)
                services+=("mealie" "firefly" "wger" "immich-server")
                ;;
            media)
                services+=("kavita" "navidrome")
                ;;
            monitoring)
                services+=("cockpit" "dozzle" "wud" "speedtest-tracker" "uptime-kuma" "netdata" "portainer" "komodo" "duplicati")
                ;;
            automation)
                services+=("homeassistant" "nodered")
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
            networking)
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
                estimated_memory=$((estimated_memory + 12))
                estimated_disk=$((estimated_disk + 20))
                ;;
            personal)
                estimated_memory=$((estimated_memory + 6))
                estimated_disk=$((estimated_disk + 20))
                ;;
            media)
                estimated_memory=$((estimated_memory + 2))
                estimated_disk=$((estimated_disk + 10))
                ;;
            monitoring)
                estimated_memory=$((estimated_memory + 4))
                estimated_disk=$((estimated_disk + 10))
                ;;
            automation)
                estimated_memory=$((estimated_memory + 2))
                estimated_disk=$((estimated_disk + 5))
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
