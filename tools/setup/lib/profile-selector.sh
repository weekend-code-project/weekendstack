#!/bin/bash
# Profile and service selection for WeekendStack
# Allows users to choose which services to deploy

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Profile definitions (from profile-matrix.md)
declare -A PROFILES=(
    ["all"]="All services (default profile)"
    ["core"]="Essential services (Glance, Vaultwarden, Link Router)"
    ["ai"]="AI & LLM services (Ollama, Open WebUI, etc.)"
    ["dev"]="Development tools (Coder, Gitea, GitLab)"
    ["productivity"]="Productivity apps (Paperless, N8N, NocoDB, etc.)"
    ["personal"]="Personal services (Mealie, Firefly, Immich, wger)"
    ["media"]="Media services (Kavita, Navidrome)"
    ["monitoring"]="Monitoring tools (Portainer, Uptime Kuma, etc.)"
    ["automation"]="Home automation (Home Assistant, Node-RED)"
    ["networking"]="Network services (Traefik, Pi-hole, Cloudflare)"
)

# Service counts per profile (approximate)
declare -A PROFILE_SERVICE_COUNTS=(
    ["all"]="65+"
    ["core"]="3"
    ["ai"]="11"
    ["dev"]="8"
    ["productivity"]="24"
    ["personal"]="7"
    ["media"]="2"
    ["monitoring"]="9"
    ["automation"]="3"
    ["networking"]="6"
)

# Profile order for display
PROFILE_ORDER=("all" "core" "networking" "ai" "dev" "productivity" "personal" "media" "monitoring" "automation")

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

select_profiles_interactive() {
    show_profile_matrix
    
    echo "Select deployment profiles:"
    echo "  • Use arrow keys to navigate"
    echo "  • Press SPACE to toggle selection"
    echo "  • Press 'a' to select all, 'n' to select none"
    echo "  • Press ENTER when done"
    echo ""
    
    local profile_list=()
    for profile in "${PROFILE_ORDER[@]}"; do
        profile_list+=("$profile - ${PROFILE_SERVICE_COUNTS[$profile]} services")
    done
    
    local selected_indices
    selected_indices=$(prompt_multiselect "Choose profiles:" "${profile_list[@]}")
    
    local selected_profiles=()
    for idx in $selected_indices; do
        selected_profiles+=("${PROFILE_ORDER[$idx]}")
    done
    
    if [[ ${#selected_profiles[@]} -eq 0 ]]; then
        log_warn "No profiles selected, defaulting to 'all'"
        selected_profiles=("all")
    fi
    
    echo ""
    log_success "Selected profiles: ${selected_profiles[*]}"
    echo ""
    
    echo "${selected_profiles[@]}"
}

select_profiles_quick() {
    log_header "Quick Profile Selection"
    
    echo "Available quick deployment options:"
    echo "  1) Minimal      - Core services only (Glance, Vaultwarden)"
    echo "  2) Developer    - Core + Dev + AI services"
    echo "  3) Productivity - Core + Productivity + Personal services"
    echo "  4) Complete     - All services (default)"
    echo "  5) Custom       - Choose specific profiles"
    echo ""
    
    local choice
    choice=$(prompt_select "Select deployment type:" "Minimal" "Developer" "Productivity" "Complete" "Custom")
    
    local selected_profiles=()
    
    case $choice in
        0) # Minimal
            selected_profiles=("core" "networking")
            ;;
        1) # Developer
            selected_profiles=("core" "networking" "dev" "ai")
            ;;
        2) # Productivity
            selected_profiles=("core" "networking" "productivity" "personal")
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
    fi
    
    return 0
}

# Export functions
export -f show_profile_matrix select_profiles_interactive select_profiles_quick
export -f get_services_for_profiles estimate_resources check_system_resources
