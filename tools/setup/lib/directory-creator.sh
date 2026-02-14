#!/bin/bash
# Directory creator for WeekendStack
# Creates all necessary directories with correct permissions

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Base directories that must exist
REQUIRED_BASE_DIRS=(
    "config"
    "data"
    "files"
    "_trash"
)

# Configuration subdirectories
CONFIG_SUBDIRS=(
    "traefik/auth"
    "traefik/certs"
    "traefik/middleware"
    "cloudflare"
    "ssh"
    "glance"
    "coder/templates"
    "coder/scripts"
    "pihole/etc-dnsmasq.d"
    "filebrowser"
    "guacamole"
    "homer"
    "link-router"
    "postiz"
    "resourcespace"
    "searxng"
    "wger"
    "diffrhythm"
)

# User files directories (based on selected profiles)
get_files_subdirs_for_profiles() {
    local profiles=("$@")
    local dirs=()
    
    # Common directories
    dirs+=("ai-models/ollama")
    
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|ai)
                dirs+=("stable-diffusion/models" "stable-diffusion/outputs")
                dirs+=("diffrhythm/models" "diffrhythm/output")
                ;;
            all|dev)
                dirs+=("coder/workspace" "coder/templates")
                ;;
            all|productivity)
                dirs+=("paperless/media" "paperless/consume" "paperless/export")
                dirs+=("postiz/uploads")
                dirs+=("resourcespace")
                ;;
            all|media)
                dirs+=("navidrome/music")
                dirs+=("kavita/library")
                ;;
        esac
    done
    
    # Remove duplicates
    local unique_dirs=($(echo "${dirs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    echo "${unique_dirs[@]}"
}

create_base_directories() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    log_step "Checking base directory structure..."
    
    local created=0
    local exists=0
    
    for dir in "${REQUIRED_BASE_DIRS[@]}"; do
        local full_path="$stack_dir/$dir"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            created=$((created + 1))
        else
            exists=$((exists + 1))
        fi
    done
    
    if [[ $created -gt 0 ]]; then
        log_success "Created $created base directories"
    fi
    if [[ $exists -gt 0 ]]; then
        log_info "$exists base directories already exist"
    fi
}

create_config_directories() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    log_step "Checking configuration directories..."
    
    local created=0
    local exists=0
    
    for subdir in "${CONFIG_SUBDIRS[@]}"; do
        local full_path="$stack_dir/config/$subdir"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            created=$((created + 1))
        else
            exists=$((exists + 1))
        fi
    done
    
    if [[ $created -gt 0 ]]; then
        log_success "Created $created configuration directories"
    fi
    if [[ $exists -gt 0 ]]; then
        log_info "$exists configuration directories already exist"
    fi
    
    # Special permissions for certain directories
    local traefik_auth_dir="$stack_dir/config/traefik/auth"
    if [[ -d "$traefik_auth_dir" ]]; then
        chmod 755 "$traefik_auth_dir"
    fi
}

create_files_directories() {
    local stack_dir="${SCRIPT_DIR}/.."
    local profiles=("$@")
    
    log_step "Checking user files directories..."
    
    # Get FILES_BASE_DIR from .env if it exists
    local files_base_dir="$stack_dir/files"
    if [[ -f "$stack_dir/.env" ]]; then
        local env_files_dir=$(grep "^FILES_BASE_DIR=" "$stack_dir/.env" | cut -d'=' -f2)
        if [[ -n "$env_files_dir" ]]; then
            # Handle relative paths
            if [[ "$env_files_dir" == ./* ]]; then
                files_base_dir="$stack_dir/${env_files_dir#./}"
            elif [[ "$env_files_dir" == /* ]]; then
                files_base_dir="$env_files_dir"
            else
                files_base_dir="$stack_dir/$env_files_dir"
            fi
        fi
    fi
    
    local subdirs=($(get_files_subdirs_for_profiles "${profiles[@]}"))
    local created=0
    local exists=0
    
    for subdir in "${subdirs[@]}"; do
        local full_path="$files_base_dir/$subdir"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            created=$((created + 1))
        else
            exists=$((exists + 1))
        fi
    done
    
    if [[ $created -gt 0 ]]; then
        log_success "Created $created user files directories"
    fi
    if [[ $exists -gt 0 ]]; then
        log_info "$exists user files directories already exist"
    fi
    
    # Set ownership to PUID:PGID from .env
    if [[ -f "$stack_dir/.env" ]]; then
        local puid=$(grep "^PUID=" "$stack_dir/.env" | cut -d'=' -f2)
        local pgid=$(grep "^PGID=" "$stack_dir/.env" | cut -d'=' -f2)
        
        if [[ -n "$puid" && -n "$pgid" ]]; then
            chown -R "$puid:$pgid" "$files_base_dir" 2>/dev/null || \
                log_info "Ownership will be set when services start"
        fi
    fi
}

create_workspace_directory() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    # Get WORKSPACE_DIR from .env
    if [[ ! -f "$stack_dir/.env" ]]; then
        return 0
    fi
    
    local workspace_dir=$(grep "^WORKSPACE_DIR=" "$stack_dir/.env" | cut -d'=' -f2)
    
    if [[ -z "$workspace_dir" ]]; then
        return 0
    fi
    
    log_step "Creating Coder workspace directory..."
    
    if [[ ! -d "$workspace_dir" ]]; then
        mkdir -p "$workspace_dir" 2>/dev/null || {
            log_warn "Cannot create $workspace_dir (may need sudo or parent directory doesn't exist)"
            return 1
        }
        log_success "Created: $workspace_dir"
    else
        log_info "Exists: $workspace_dir"
    fi
    
    # Set ownership
    local puid=$(grep "^PUID=" "$stack_dir/.env" | cut -d'=' -f2)
    local pgid=$(grep "^PGID=" "$stack_dir/.env" | cut -d'=' -f2)
    
    if [[ -n "$puid" && -n "$pgid" ]]; then
        chown -R "$puid:$pgid" "$workspace_dir" 2>/dev/null || \
            log_warn "Could not set ownership on workspace directory (may need sudo)"
    fi
}

create_ssh_directory() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    # Get SSH_KEY_DIR from .env
    if [[ ! -f "$stack_dir/.env" ]]; then
        return 0
    fi
    
    local ssh_key_dir=$(grep "^SSH_KEY_DIR=" "$stack_dir/.env" | cut -d'=' -f2)
    
    # Expand variables in path
    if [[ "$ssh_key_dir" == *'${'* ]]; then
        local config_base_dir=$(grep "^CONFIG_BASE_DIR=" "$stack_dir/.env" | cut -d'=' -f2)
        ssh_key_dir="${ssh_key_dir//\$\{CONFIG_BASE_DIR\}/$config_base_dir}"
    fi
    
    if [[ -z "$ssh_key_dir" ]]; then
        return 0
    fi
    
    # Make absolute if relative
    if [[ "$ssh_key_dir" == ./* ]]; then
        ssh_key_dir="$stack_dir/${ssh_key_dir#./}"
    fi
    
    log_step "Checking SSH key directory..."
    
    if [[ ! -d "$ssh_key_dir" ]]; then
        mkdir -p "$ssh_key_dir"
        chmod 700 "$ssh_key_dir"
        log_success "Created: $ssh_key_dir (permissions: 700)"
    else
        log_info "Exists: $ssh_key_dir"
    fi
    
    # Check if SSH keys exist
    if [[ ! -f "$ssh_key_dir/id_rsa" && ! -f "$ssh_key_dir/id_ed25519" ]]; then
        echo ""
        log_warn "No SSH keys found in $ssh_key_dir"
        if prompt_yes_no "Generate new SSH key pair?" "y"; then
            generate_ssh_key "$ssh_key_dir"
        else
            log_info "You can manually copy SSH keys to: $ssh_key_dir"
        fi
    fi
}

generate_ssh_key() {
    local ssh_dir="$1"
    
    echo ""
    local key_type
    key_type=$(prompt_select "SSH key type:" "ed25519 (recommended)" "rsa 4096")
    
    local key_comment
    key_comment=$(prompt_input "Key comment (e.g., email)" "weekendstack@$(hostname)")
    
    case $key_type in
        0) # ed25519
            ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -C "$key_comment" -N ""
            log_success "Generated ed25519 key pair"
            ;;
        1) # rsa
            ssh-keygen -t rsa -b 4096 -f "$ssh_dir/id_rsa" -C "$key_comment" -N ""
            log_success "Generated RSA 4096 key pair"
            ;;
    esac
    
    chmod 600 "$ssh_dir"/id_* 2>/dev/null
    chmod 644 "$ssh_dir"/*.pub 2>/dev/null
}

validate_directory_structure() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    log_step "Validating directory structure..."
    
    local errors=0
    
    # Check base directories
    for dir in "${REQUIRED_BASE_DIRS[@]}"; do
        if [[ ! -d "$stack_dir/$dir" ]]; then
            log_error "Missing: $dir/"
            errors=$((errors + 1))
        fi
    done
    
    # Check critical config directories
    local critical_dirs=("config/traefik" "config/cloudflare")
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$stack_dir/$dir" ]]; then
            log_error "Missing: $dir/"
            errors=$((errors + 1))
        fi
    done
    
    if ((errors > 0)); then
        log_error "Directory validation failed with $errors errors"
        return 1
    fi
    
    log_success "Directory structure validated"
    return 0
}

setup_all_directories() {
    local profiles=("$@")
    
    log_header "Directory Setup"
    
    create_base_directories
    create_config_directories
    create_files_directories "${profiles[@]}"
    create_workspace_directory
    create_ssh_directory
    
    echo ""
    validate_directory_structure
    
    log_success "Directory setup complete"
}

# Export functions
export -f get_files_subdirs_for_profiles create_base_directories
export -f create_config_directories create_files_directories
export -f create_workspace_directory create_ssh_directory
export -f generate_ssh_key validate_directory_structure setup_all_directories
