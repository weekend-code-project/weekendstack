#!/bin/bash
# Directory creator for WeekendStack
# Creates all necessary directories with correct permissions

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Base directories that must exist
REQUIRED_BASE_DIRS=(
    "config"
    "data"
    "files"
)

# Configuration subdirectories
CONFIG_SUBDIRS=(
    "traefik/auth"
    "traefik/certs"
    "traefik/middleware"
    "cloudflare"
    "ssh"
    "glance"
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
    
    # Check if 'all' profile is selected — if so, include everything
    local include_all=false
    for profile in "${profiles[@]}"; do
        if [[ "$profile" == "all" ]]; then
            include_all=true
            break
        fi
    done
    
    for profile in "${profiles[@]}"; do
        case "$profile" in
            ai)
                dirs+=("stable-diffusion/models" "stable-diffusion/outputs")
                dirs+=("diffrhythm/models" "diffrhythm/output")
                ;;
            dev)
                dirs+=("coder/workspace" "coder/templates")
                ;;
            productivity)
                dirs+=("paperless/media" "paperless/consume" "paperless/export")
                dirs+=("postiz/uploads")
                dirs+=("resourcespace")
                ;;
            media)
                dirs+=("navidrome/music")
                dirs+=("kavita/library")
                ;;
        esac
    done
    
    # If 'all' profile, add everything that wasn't matched above
    if $include_all; then
        dirs+=("stable-diffusion/models" "stable-diffusion/outputs")
        dirs+=("diffrhythm/models" "diffrhythm/output")
        dirs+=("coder/workspace" "coder/templates")
        dirs+=("paperless/media" "paperless/consume" "paperless/export")
        dirs+=("postiz/uploads")
        dirs+=("resourcespace")
        dirs+=("navidrome/music")
        dirs+=("kavita/library")
    fi
    
    # Remove duplicates
    local unique_dirs=($(echo "${dirs[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    echo "${unique_dirs[@]}"
}

create_base_directories() {
    local stack_dir="${SCRIPT_DIR}"
    
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
    local stack_dir="${SCRIPT_DIR}"
    
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

    # Pre-create files that must be FILES (not directories) before Docker starts.
    # Docker silently creates a directory at a bind-mount source path if the file is missing.
    # For files with .example counterparts, copy the example; otherwise create a placeholder.
    _ensure_from_example "$stack_dir/config/glance/glance.yml"
    _ensure_from_example "$stack_dir/config/filebrowser/init-filebrowser.sh"

    # Traefik config.yml — copy from .example if missing or empty.
    _ensure_traefik_static_config "$stack_dir/config/traefik/config.yml"

    # Copy coder deploy scripts from tools/coder/scripts -> config/coder/scripts.
    # tools/ is the source of truth; config/ holds the active copy.
    # This runs on every setup so uninstall can safely delete config/coder/scripts/.
    local coder_scripts_src="$stack_dir/tools/coder/scripts"
    local coder_scripts_dst="$stack_dir/config/coder/scripts"
    if [[ -d "$coder_scripts_src" ]]; then
        mkdir -p "$coder_scripts_dst/lib"
        cp -r "$coder_scripts_src"/. "$coder_scripts_dst/"
        chmod +x "$coder_scripts_dst"/*.sh "$coder_scripts_dst/lib"/*.sh 2>/dev/null || true
        log_info "Deployed coder scripts from tools/coder/scripts"
    fi
}

# Ensure a path is a file, not a directory.
# Docker creates a directory at a missing bind-mount source — this reverses that.
# Use _ensure_from_example instead when there is a .example counterpart.
_ensure_file_not_dir() {
    local file_path="$1"
    local dir_path
    dir_path=$(dirname "$file_path")

    if [[ -d "$file_path" ]]; then
        rmdir "$file_path" 2>/dev/null || rm -rf "$file_path"
        log_info "Removed phantom directory at: $file_path"
    fi

    if [[ ! -f "$file_path" ]]; then
        mkdir -p "$dir_path"
        touch "$file_path"
        log_info "Pre-created placeholder file: $file_path"
    fi
}

# Ensure a config file exists by copying from its .example counterpart.
# If no .example exists, falls back to an empty placeholder.
# Safe to call on every setup — never overwrites an existing file.
_ensure_from_example() {
    local file_path="$1"
    local example_path="${file_path}.example"
    local dir_path
    dir_path=$(dirname "$file_path")

    # Fix phantom directory left by Docker
    if [[ -d "$file_path" ]]; then
        rmdir "$file_path" 2>/dev/null || rm -rf "$file_path"
        log_info "Removed phantom directory at: $file_path"
    fi

    if [[ ! -f "$file_path" ]]; then
        mkdir -p "$dir_path"
        if [[ -f "$example_path" ]]; then
            if cp "$example_path" "$file_path" 2>/dev/null; then
                log_info "Created $(basename "$file_path") from .example template"
            else
                log_warn "Cannot write $(basename "$file_path") — permission denied"
                log_warn "  Fix: sudo cp '$example_path' '$file_path'"
            fi
        else
            if touch "$file_path" 2>/dev/null; then
                log_info "Pre-created placeholder file (no .example found): $file_path"
            else
                log_warn "Cannot create placeholder file: $file_path — permission denied"
            fi
        fi
    fi
}

# Ensure traefik config.yml contains a valid static configuration.
# An empty config.yml means traefik starts without entrypoints (no ports 80/443)
# and without the Docker provider (can't discover container labels).
_ensure_traefik_static_config() {
    local config_path="$1"
    local dir_path
    dir_path=$(dirname "$config_path")

    # Fix phantom directory
    if [[ -d "$config_path" ]]; then
        rmdir "$config_path" 2>/dev/null || rm -rf "$config_path"
        log_info "Removed phantom directory at: $config_path"
    fi

    # Write config if missing or empty (placeholder from previous setup)
    if [[ ! -s "$config_path" ]] || ! grep -q "entryPoints" "$config_path" 2>/dev/null; then
        mkdir -p "$dir_path"
        local example_path="${config_path}.example"
        if [[ -f "$example_path" ]]; then
            cp "$example_path" "$config_path"
            log_info "Created traefik static config from .example: $config_path"
        else
            # Fallback if .example is somehow missing
            cat > "$config_path" << 'TRAEFIK_CONFIG'
# Traefik v3 Static Configuration
log:
  level: INFO

api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    endpoint: "unix:///var/run/docker.sock"
  file:
    directory: /config/traefik/auth
    watch: true
TRAEFIK_CONFIG
            log_info "Created traefik static config (no .example found): $config_path"
        fi
    fi
}

create_files_directories() {
    local stack_dir="${SCRIPT_DIR}"
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
            # Try without sudo first; fall back to sudo for root-owned dirs
            if ! chown -R "$puid:$pgid" "$files_base_dir" 2>/dev/null; then
                log_info "Some directories are root-owned (created by Docker), using sudo to fix ownership..."
                sudo chown -R "$puid:$pgid" "$files_base_dir" 2>/dev/null || \
                    log_warn "Could not fix ownership on $files_base_dir — run: sudo chown -R $puid:$pgid $files_base_dir"
            fi
        fi
    fi
}

create_workspace_directory() {
    local stack_dir="${SCRIPT_DIR}"
    
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
    local stack_dir="${SCRIPT_DIR}"
    
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
    local stack_dir="${SCRIPT_DIR}"
    
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

    local _dir_errors=0

    create_base_directories
    create_config_directories || _dir_errors=$((_dir_errors + 1))
    create_files_directories "${profiles[@]}"
    create_workspace_directory

    echo ""
    validate_directory_structure

    echo ""
    if (( _dir_errors > 0 )); then
        log_warn "Directory setup completed with $_dir_errors permission warning(s) above."
        log_warn "Review the warnings and fix with 'sudo' as needed before starting services."
    else
        log_success "Directory setup complete — all paths are ready."
    fi
    echo ""
    read -rp "  Press Enter to continue..." </dev/tty
}

# Export functions
export -f get_files_subdirs_for_profiles create_base_directories
export -f create_config_directories create_files_directories _ensure_file_not_dir
export -f create_workspace_directory create_ssh_directory
export -f generate_ssh_key validate_directory_structure setup_all_directories
