#!/bin/bash
# Registry cache bootstrap and management
# Handles pull-through Docker registry cache for setup optimization

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Registry cache configuration
REGISTRY_CACHE_SERVICE="registry-cache"
REGISTRY_CACHE_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_CACHE_URL="http://localhost:${REGISTRY_CACHE_PORT}"
DAEMON_CONFIG_BACKUP="/tmp/docker-daemon.json.backup"
DAEMON_CONFIG_CREATED_MARKER="/tmp/docker-daemon.json.created-by-weekendstack"

registry_cache_dir() {
    local lib_dir repo_root data_dir

    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="${SCRIPT_DIR:-$(cd "$lib_dir/../../.." && pwd)}"
    data_dir="${DATA_BASE_DIR:-$repo_root/data}"

    echo "${REGISTRY_DATA_DIR:-$data_dir/registry-cache}"
}

daemon_config_is_cache_only() {
    local config_path="$1"

    sudo jq -e --arg mirror "$REGISTRY_CACHE_URL" '
        ((keys | sort) == ["registry-mirrors"]) and
        (
            (.["registry-mirrors"] == [$mirror]) or
            (.["registry-mirrors"] == [($mirror + "/")])
        )
    ' "$config_path" >/dev/null 2>&1
}

# Check if registry cache is running
is_cache_running() {
    docker compose ps -q "$REGISTRY_CACHE_SERVICE" 2>/dev/null | grep -q .
}

# Check if registry cache is healthy
is_cache_healthy() {
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf "${REGISTRY_CACHE_URL}/v2/" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    
    return 1
}

docker_mirror_configured() {
    local daemon_config="/etc/docker/daemon.json"

    if docker info 2>/dev/null | awk '/Registry Mirrors:/,/Live Restore Enabled:/' | \
       grep -q "http://localhost:${REGISTRY_CACHE_PORT}/\?"; then
        return 0
    fi

    if [[ -f "$daemon_config" ]] && daemon_config_is_cache_only "$daemon_config"; then
        return 0
    fi

    return 1
}

prepare_registry_cache_for_startup() {
    local needs_cache=false

    if docker_mirror_configured; then
        needs_cache=true
    fi

    if docker compose config 2>/dev/null | grep -q '^[[:space:]]*build:'; then
        needs_cache=true
    fi

    if [[ "$needs_cache" != "true" ]]; then
        return 0
    fi

    if is_cache_running && is_cache_healthy; then
        return 0
    fi

    log_step "Ensuring registry cache is available before starting services..."

    if start_registry_cache; then
        return 0
    fi

    if docker_mirror_configured; then
        log_warn "Registry cache could not be started; restoring Docker mirror configuration so pulls fall back to Docker Hub"
        restore_docker_config || true
    fi

    return 0
}

# Start registry cache service
start_registry_cache() {
    log_header "Starting Registry Cache"
    
    # Check if already running
    if is_cache_running; then
        log_info "Registry cache already running"
        # Still ensure the Docker mirror is configured (may have been lost after restart)
        configure_docker_mirror
        return 0
    fi
    
    log_step "Starting pull-through cache for Docker Hub images..."
    echo "  This cache will significantly reduce rate limit issues"
    echo "  and speed up repeated image pulls during setup."
    echo ""
    
    # Ensure required directories exist
    local cache_dir
    cache_dir="$(registry_cache_dir)"
    mkdir -p "$cache_dir"
    
    # Set environment variable for the service
    export REGISTRY_DATA_DIR="$cache_dir"
    
    # Start only the registry-cache service with setup-infrastructure profile
    local compose_output
    compose_output=$(docker compose --profile setup-infrastructure up -d "$REGISTRY_CACHE_SERVICE" 2>&1)
    local compose_exit=$?
    
    # Check for network label mismatch errors
    if echo "$compose_output" | grep -q "has incorrect label"; then
        log_info "Detected outdated network labels, refreshing networks..."
        
        # Remove existing networks (they'll be recreated with correct labels)
        docker network rm shared-network coder-network traefik-network 2>/dev/null || true
        
        # Retry starting the service
        compose_output=$(docker compose --profile setup-infrastructure up -d "$REGISTRY_CACHE_SERVICE" 2>&1)
        compose_exit=$?
    fi
    
    if [[ $compose_exit -eq 0 ]]; then
        log_step "Waiting for cache to become healthy..."
        
        if is_cache_healthy; then
            log_success "Registry cache is ready at ${REGISTRY_CACHE_URL}"
            
            # Configure Docker to use the cache as a mirror
            configure_docker_mirror
            
            return 0
        else
            log_error "Registry cache failed to become healthy"
            echo "$compose_output" | grep -i "error" || echo "$compose_output"
            return 1
        fi
    else
        log_error "Failed to start registry cache"
        echo "$compose_output" | grep -i "error" || echo "$compose_output"
        return 1
    fi
}

# Stop registry cache service
stop_registry_cache() {
    local keep_cache="${1:-false}"
    
    if ! is_cache_running; then
        return 0
    fi
    
    if [[ "$keep_cache" == "true" ]]; then
        log_info "Keeping registry cache running (--keep-cache specified)"
        return 0
    fi
    
    log_step "Stopping registry cache..."
    
    # Restore Docker daemon config
    restore_docker_config
    
    # Stop the service
    docker compose stop "$REGISTRY_CACHE_SERVICE" >/dev/null 2>&1
    docker compose rm -f "$REGISTRY_CACHE_SERVICE" >/dev/null 2>&1
    
    log_success "Registry cache stopped"
}

# Configure Docker daemon to use registry as mirror
configure_docker_mirror() {
    # Note: This modifies /etc/docker/daemon.json temporarily
    # We'll restore it after setup completes
    
    local daemon_config="/etc/docker/daemon.json"
    
    # Check if we have permission to modify daemon config
    # Direct write access not needed if passwordless sudo is available
    if [[ ! -w "$daemon_config" ]] && [[ ! -w "$(dirname "$daemon_config")" ]]; then
        if ! sudo -n true 2>/dev/null; then
            log_warn "Cannot configure Docker mirror (no write access to /etc/docker/ and sudo unavailable)"
            log_warn "Docker Hub pulls will go directly to the registry"
            return 0
        fi
    fi
    
    # Backup existing config or remember that we created daemon.json from scratch.
    if [[ -f "$daemon_config" ]]; then
        if daemon_config_is_cache_only "$daemon_config"; then
            sudo rm -f "$DAEMON_CONFIG_BACKUP" 2>/dev/null || true
            : > "$DAEMON_CONFIG_CREATED_MARKER"
        else
            rm -f "$DAEMON_CONFIG_CREATED_MARKER"
            sudo cp "$daemon_config" "$DAEMON_CONFIG_BACKUP" 2>/dev/null || {
                log_warn "Cannot backup daemon config (continuing without mirror configuration)"
                return 0
            }
        fi
    else
        : > "$DAEMON_CONFIG_CREATED_MARKER"
    fi
    
    log_step "Configuring Docker to use registry cache as mirror..."
    
    # Create or update daemon.json with registry-mirrors
    local temp_config="/tmp/daemon.json.tmp"
    
    if [[ -f "$daemon_config" ]]; then
        # Merge with existing config (simple approach - just add registry-mirrors)
        sudo jq ". + {\"registry-mirrors\": [\"${REGISTRY_CACHE_URL}\"]}" "$daemon_config" > "$temp_config" 2>/dev/null || {
            log_warn "Cannot update daemon config (jq not available or config invalid)"
            return 0
        }
    else
        # Create new config
        echo "{\"registry-mirrors\": [\"${REGISTRY_CACHE_URL}\"]}" > "$temp_config"
    fi
    
    # Apply the configuration
    sudo mv "$temp_config" "$daemon_config" 2>/dev/null || {
        log_warn "Cannot apply daemon config (continuing without mirror configuration)"
        return 0
    }
    
    # Reload Docker daemon
    log_step "Reloading Docker daemon..."
    sudo systemctl reload docker 2>/dev/null || sudo pkill -SIGHUP dockerd 2>/dev/null || {
        log_warn "Cannot reload Docker daemon (mirror config may not be active)"
        return 0
    }
    
    sleep 2
    log_success "Docker configured to use registry cache"
}

# Restore original Docker daemon configuration
restore_docker_config() {
    local daemon_config="/etc/docker/daemon.json"
    local temp_config="/tmp/daemon.json.restore.tmp"
    
    log_step "Restoring Docker daemon configuration..."

    if [[ -f "$DAEMON_CONFIG_BACKUP" ]] && [[ -f "$daemon_config" ]] && \
       daemon_config_is_cache_only "$DAEMON_CONFIG_BACKUP" && daemon_config_is_cache_only "$daemon_config"; then
        sudo rm -f "$DAEMON_CONFIG_BACKUP" 2>/dev/null || true
        : > "$DAEMON_CONFIG_CREATED_MARKER"
    fi

    if [[ -f "$DAEMON_CONFIG_BACKUP" ]]; then
        sudo mv "$DAEMON_CONFIG_BACKUP" "$daemon_config" 2>/dev/null || {
            log_warn "Cannot restore daemon config"
            return 1
        }
        rm -f "$DAEMON_CONFIG_CREATED_MARKER"
    elif [[ -f "$DAEMON_CONFIG_CREATED_MARKER" ]]; then
        sudo rm -f "$daemon_config" 2>/dev/null || {
            log_warn "Cannot remove daemon config created for registry mirror"
            return 1
        }
        rm -f "$DAEMON_CONFIG_CREATED_MARKER"
    elif [[ -f "$daemon_config" ]]; then
        # Migration path for older runs that created daemon.json but did not
        # leave a backup/marker. Remove only the WeekendStack registry mirror.
        sudo jq --arg mirror "$REGISTRY_CACHE_URL" '
            .["registry-mirrors"] =
                ((.["registry-mirrors"] // [])
                | map(select(. != $mirror and . != ($mirror + "/"))))
            | if (.["registry-mirrors"] | length) == 0 then del(.["registry-mirrors"]) else . end
        ' "$daemon_config" > "$temp_config" 2>/dev/null || {
            rm -f "$temp_config"
            log_warn "Cannot clean registry mirror from daemon config"
            return 1
        }

        if sudo jq -e 'keys | length == 0' "$temp_config" >/dev/null 2>&1; then
            sudo rm -f "$daemon_config" "$temp_config" 2>/dev/null || {
                log_warn "Cannot remove empty daemon config"
                return 1
            }
        else
            sudo mv "$temp_config" "$daemon_config" 2>/dev/null || {
                rm -f "$temp_config"
                log_warn "Cannot update daemon config while removing registry mirror"
                return 1
            }
        fi
    else
        return 0
    fi
    
    # Restart Docker so runtime mirror state is fully cleared after removing
    # daemon.json entries. A reload leaves stale mirrors visible in `docker info`.
    sudo systemctl restart docker 2>/dev/null || sudo systemctl reload docker 2>/dev/null || sudo pkill -SIGHUP dockerd 2>/dev/null
    
    sleep 2
    log_success "Docker configuration restored"
}

# Get cache statistics
get_cache_stats() {
    if ! is_cache_running; then
        echo "Cache not running"
        return 1
    fi
    
    local cache_dir
    cache_dir="$(registry_cache_dir)"
    
    if [[ -d "$cache_dir" ]]; then
        local cache_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
        local blob_count=$(find "$cache_dir" -type f 2>/dev/null | wc -l)
        
        echo "Cache size: ${cache_size:-0}"
        echo "Cached blobs: ${blob_count:-0}"
    else
        echo "Cache directory not found"
    fi
}

# Show cache information
show_cache_info() {
    log_header "Registry Cache Information"
    
    echo "Purpose: Pull-through cache for Docker Hub images"
    echo "Benefits:"
    echo "  • Reduces Docker Hub rate limit impact"
    echo "  • Speeds up repeated image pulls"
    echo "  • Caches image layers locally"
    echo ""
    echo "Status: $(is_cache_running && echo 'Running' || echo 'Stopped')"
    
    if is_cache_running; then
        echo ""
        get_cache_stats
    fi
    
    echo ""
}

# Clear cache data
clear_cache() {
    log_step "Clearing registry cache data..."
    
    # Stop cache if running
    if is_cache_running; then
        docker compose stop "$REGISTRY_CACHE_SERVICE" >/dev/null 2>&1
    fi
    
    local cache_dir
    cache_dir="$(registry_cache_dir)"
    
    if [[ -d "$cache_dir" ]]; then
        rm -rf "$cache_dir"
        log_success "Cache data cleared"
    else
        log_info "No cache data to clear"
    fi
}

# Export functions
export -f is_cache_running
export -f is_cache_healthy
export -f registry_cache_dir
export -f docker_mirror_configured
export -f prepare_registry_cache_for_startup
export -f start_registry_cache
export -f stop_registry_cache
export -f daemon_config_is_cache_only
export -f configure_docker_mirror
export -f restore_docker_config
export -f get_cache_stats
export -f show_cache_info
export -f clear_cache
