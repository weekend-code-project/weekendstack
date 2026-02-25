#!/bin/bash
# Registry cache bootstrap and management
# Handles pull-through Docker registry cache for setup optimization

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Registry cache configuration
REGISTRY_CACHE_SERVICE="registry-cache"
REGISTRY_CACHE_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_CACHE_URL="http://localhost:${REGISTRY_CACHE_PORT}"
DAEMON_CONFIG_BACKUP="/tmp/docker-daemon.json.backup"

# Check if registry cache is running
is_cache_running() {
    docker ps --filter "name=${REGISTRY_CACHE_SERVICE}" --format "{{.Names}}" 2>/dev/null | grep -q "^${REGISTRY_CACHE_SERVICE}$"
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

# Start registry cache service
start_registry_cache() {
    log_header "Starting Registry Cache"
    
    # Check if already running
    if is_cache_running; then
        log_info "Registry cache already running"
        return 0
    fi
    
    log_step "Starting pull-through cache for Docker Hub images..."
    echo "  This cache will significantly reduce rate limit issues"
    echo "  and speed up repeated image pulls during setup."
    echo ""
    
    # Ensure required directories exist
    local cache_dir="${DATA_BASE_DIR:-$SCRIPT_DIR/data}/registry-cache"
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
    if [[ ! -w "$daemon_config" ]] && [[ ! -w "$(dirname "$daemon_config")" ]]; then
        log_info "Running without daemon config modification (works fine via explicit config)"
        log_info "Registry cache will still work for all image pulls"
        return 0
    fi
    
    # Backup existing config
    if [[ -f "$daemon_config" ]]; then
        sudo cp "$daemon_config" "$DAEMON_CONFIG_BACKUP" 2>/dev/null || {
            log_warn "Cannot backup daemon config (continuing without mirror configuration)"
            return 0
        }
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
    
    if [[ ! -f "$DAEMON_CONFIG_BACKUP" ]]; then
        return 0
    fi
    
    log_step "Restoring Docker daemon configuration..."
    
    sudo mv "$DAEMON_CONFIG_BACKUP" "$daemon_config" 2>/dev/null || {
        log_warn "Cannot restore daemon config"
        return 1
    }
    
    # Reload Docker daemon
    sudo systemctl reload docker 2>/dev/null || sudo pkill -SIGHUP dockerd 2>/dev/null
    
    sleep 2
    log_success "Docker configuration restored"
}

# Get cache statistics
get_cache_stats() {
    if ! is_cache_running; then
        echo "Cache not running"
        return 1
    fi
    
    local cache_dir="${DATA_BASE_DIR:-$SCRIPT_DIR/data}/registry-cache"
    
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
    
    local cache_dir="${DATA_BASE_DIR:-$SCRIPT_DIR/data}/registry-cache"
    
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
export -f start_registry_cache
export -f stop_registry_cache
export -f configure_docker_mirror
export -f restore_docker_config
export -f get_cache_stats
export -f show_cache_info
export -f clear_cache
