#!/bin/bash
# Docker authentication for multiple registries
# Sources: Docker Hub, GitHub Container Registry, Google Container Registry

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Registry URLs
declare -A REGISTRY_URLS=(
    ["dockerhub"]="docker.io"
    ["github"]="ghcr.io"
    ["google"]="gcr.io"
)

docker_login_hub() {
    log_step "Docker Hub Authentication"
    
    # Check if already authenticated by looking at config file
    local config_file="$HOME/.docker/config.json"
    if [[ -f "$config_file" ]] && grep -q '"docker.io"\|"https://index.docker.io"' "$config_file" 2>/dev/null; then
        local docker_user=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
        if [[ -n "$docker_user" ]]; then
            log_info "Already authenticated with Docker Hub as: $docker_user"
            return 0
        fi
    fi
    
    echo ""
    echo "Enter your Docker Hub credentials (FREE account works fine):"
    echo "  • Create account at: https://hub.docker.com/signup"
    echo "  • This is ONLY for rate limit protection on public images"
    echo "  • Press Enter with empty username to skip"
    echo ""
    
    local username
    local password
    
    username=$(prompt_input "Docker Hub username" "")
    
    if [[ -z "$username" ]]; then
        log_warn "Skipped Docker Hub authentication"
        return 0
    fi
    
    read -r -s -p "$(echo -e ${CYAN}?${NC}) Docker Hub password or token: " password
    echo ""
    
    if [[ -z "$password" ]]; then
        log_warn "Skipped Docker Hub authentication (no password provided)"
        return 0
    fi
    
    if echo "$password" | docker login -u "$username" --password-stdin 2>/dev/null; then
        log_success "Successfully authenticated with Docker Hub"
        return 0
    else
        log_error "Failed to authenticate with Docker Hub"
        return 1
    fi
}

docker_login_ghcr() {
    log_step "Checking GitHub Container Registry authentication..."
    
    if docker-credential-helpers-check ghcr.io 2>/dev/null; then
        log_info "Already authenticated with GitHub Container Registry"
        return 0
    fi
    
    if ! prompt_yes_no "Authenticate with GitHub Container Registry (ghcr.io)?" "n"; then
        return 0
    fi
    
    echo ""
    echo "GitHub Container Registry requires a Personal Access Token (PAT)"
    echo "Create one at: https://github.com/settings/tokens"
    echo "Required scope: read:packages"
    echo ""
    
    local username
    local token
    
    username=$(prompt_input "GitHub username" "")
    
    if [[ -z "$username" ]]; then
        log_warn "Skipping GitHub Container Registry authentication"
        return 0
    fi
    
    read -r -s -p "$(echo -e ${CYAN}?${NC}) GitHub Personal Access Token: " token
    echo ""
    
    if [[ -z "$token" ]]; then
        log_warn "Skipping GitHub Container Registry authentication"
        return 0
    fi
    
    if echo "$token" | docker login ghcr.io -u "$username" --password-stdin 2>/dev/null; then
        log_success "Successfully authenticated with GitHub Container Registry"
        return 0
    else
        log_error "Failed to authenticate with GitHub Container Registry"
        return 1
    fi
}

docker_login_gcr() {
    log_step "Checking Google Container Registry authentication..."
    
    if ! prompt_yes_no "Authenticate with Google Container Registry (gcr.io)?" "n"; then
        return 0
    fi
    
    echo ""
    echo "Google Container Registry requires:"
    echo "1. A service account JSON key file, OR"
    echo "2. gcloud CLI configured with application default credentials"
    echo ""
    
    if check_command gcloud; then
        if prompt_yes_no "Use gcloud CLI for authentication?" "y"; then
            if gcloud auth configure-docker gcr.io 2>/dev/null; then
                log_success "Successfully configured gcr.io with gcloud"
                return 0
            else
                log_error "Failed to configure gcr.io with gcloud"
                return 1
            fi
        fi
    fi
    
    local key_file
    key_file=$(prompt_input "Service account JSON key file path" "")
    
    if [[ -z "$key_file" || ! -f "$key_file" ]]; then
        log_warn "Skipping Google Container Registry authentication"
        return 0
    fi
    
    if cat "$key_file" | docker login -u _json_key --password-stdin gcr.io 2>/dev/null; then
        log_success "Successfully authenticated with Google Container Registry"
        return 0
    else
        log_error "Failed to authenticate with Google Container Registry"
        return 1
    fi
}

docker_login_private() {
    if ! prompt_yes_no "Do you have a private Docker registry to authenticate with?" "n"; then
        return 0
    fi
    
    local registry_url
    local username
    local password
    
    registry_url=$(prompt_input "Private registry URL" "registry.example.com")
    username=$(prompt_input "Registry username" "")
    
    if [[ -z "$username" ]]; then
        log_warn "Skipping private registry authentication"
        return 0
    fi
    
    read -r -s -p "$(echo -e ${CYAN}?${NC}) Registry password or token: " password
    echo ""
    
    if [[ -z "$password" ]]; then
        log_warn "Skipping private registry authentication"
        return 0
    fi
    
    if echo "$password" | docker login "$registry_url" -u "$username" --password-stdin 2>/dev/null; then
        log_success "Successfully authenticated with $registry_url"
        return 0
    else
        log_error "Failed to authenticate with $registry_url"
        return 1
    fi
}

setup_docker_auth() {
    log_header "Docker Registry Authentication"
    
    # First, check current authentication status
    echo "Checking current Docker authentication status..."
    echo ""
    
    local config_file="$HOME/.docker/config.json"
    local already_authenticated=false
    
    if [[ -f "$config_file" ]]; then
        if grep -q '"auths"' "$config_file" 2>/dev/null; then
            echo "✓ Docker configuration found"
            if grep -q '"docker.io"\|"https://index.docker.io"' "$config_file" 2>/dev/null; then
                local docker_user=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
                if [[ -n "$docker_user" ]]; then
                    echo "✓ Already authenticated with Docker Hub as: $docker_user"
                    already_authenticated=true
                fi
            fi
        fi
    fi
    
    echo ""
    
    if $already_authenticated; then
        if ! prompt_yes_no "Docker Hub authentication already configured. Reconfigure?" "n"; then
            log_info "Using existing Docker authentication"
            return 0
        fi
        echo ""
    fi
    
    echo "WeekendStack pulls images from Docker Hub (docker.io)."
    echo ""
    echo "Docker Hub has rate limits:"
    echo "  • Anonymous users: 100 pulls per 6 hours"
    echo "  • Authenticated users: 200 pulls per 6 hours (FREE account)"
    echo ""
    echo "Authenticating with Docker Hub is RECOMMENDED to avoid rate limit errors."
    echo ""
    
    if ! check_command docker; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    
    # Docker Hub (recommended for rate limits)
    if prompt_yes_no "Authenticate with Docker Hub to avoid rate limits?" "y"; then
        docker_login_hub || log_warn "Docker Hub authentication failed"
    else
        log_warn "Skipping Docker Hub auth - you may hit rate limits during image pulls"
    fi
    
    # Optional: Other registries (most users won't need these)
    echo ""
    if prompt_yes_no "Do you need to authenticate with other registries? (GitHub, Google, private)" "n"; then
        echo ""
        docker_login_ghcr || true
        docker_login_gcr || true
        docker_login_private || true
    fi
    
    log_success "Docker authentication setup complete"
    return 0
}

check_docker_auth_status() {
    log_info "Checking Docker authentication status..."
    
    local config_file="$HOME/.docker/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "No Docker credentials found"
        return 1
    fi
    
    echo ""
    echo "Authenticated registries:"
    
    if grep -q "docker.io\|https://index.docker.io" "$config_file" 2>/dev/null; then
        echo "  ✓ Docker Hub (docker.io)"
    fi
    
    if grep -q "ghcr.io" "$config_file" 2>/dev/null; then
        echo "  ✓ GitHub Container Registry (ghcr.io)"
    fi
    
    if grep -q "gcr.io" "$config_file" 2>/dev/null; then
        echo "  ✓ Google Container Registry (gcr.io)"
    fi
    
    echo ""
}

# Export functions
export -f docker_login_hub docker_login_ghcr docker_login_gcr docker_login_private
export -f setup_docker_auth check_docker_auth_status
