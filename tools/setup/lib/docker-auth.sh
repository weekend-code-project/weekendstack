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

# Check Docker Hub rate limit status
check_docker_hub_limits() {
    # Get authentication token (anonymous or authenticated)
    local token=$(curl -sf "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" 2>/dev/null | jq -r '.token' 2>/dev/null)
    
    if [[ -z "$token" ]] || [[ "$token" == "null" ]]; then
        echo "STATUS=unknown"
        echo "MESSAGE=Unable to check rate limit status"
        return 0  # Non-fatal: rate limit check is informational only
    fi
    
    # Query rate limit headers
    local response=$(curl -sf -H "Authorization: Bearer $token" \
        -I "https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo "STATUS=unknown"
        echo "MESSAGE=Unable to check rate limit status"
        return 0  # Non-fatal: rate limit check is informational only
    fi
    
    # Parse rate limit headers
    local limit=$(echo "$response" | grep -i "ratelimit-limit:" | awk -F'[:;]' '{print $2}' | tr -d ' \r')
    local remaining=$(echo "$response" | grep -i "ratelimit-remaining:" | awk -F'[:;]' '{print $2}' | tr -d ' \r')
    
    if [[ -z "$limit" ]] || [[ -z "$remaining" ]]; then
        # Fallback: check if authenticated
        if docker info 2>/dev/null | grep -q "Username:"; then
            echo "STATUS=authenticated"
            echo "LIMIT=200"
            echo "REMAINING=unknown"
            echo "MESSAGE=Authenticated (200 pulls per 6 hours)"
        else
            echo "STATUS=anonymous"
            echo "LIMIT=100"
            echo "REMAINING=unknown"
            echo "MESSAGE=Anonymous (100 pulls per 6 hours)"
        fi
        return 0
    fi
    
    # Determine status color/level
    local status="ok"
    if [[ $remaining -le 10 ]]; then
        status="critical"
    elif [[ $remaining -le 50 ]]; then
        status="warning"
    fi
    
    echo "STATUS=$status"
    echo "LIMIT=$limit"
    echo "REMAINING=$remaining"
    echo "MESSAGE=$remaining of $limit pulls remaining"
    
    return 0
}

# Check if currently rate limited
is_rate_limited() {
    local limit_data=$(check_docker_hub_limits)
    
    declare -A data
    while IFS='=' read -r key value; do
        data[$key]="$value"
    done <<< "$limit_data"
    
    local remaining="${data[REMAINING]}"
    
    if [[ "$remaining" == "unknown" ]] || [[ -z "$remaining" ]]; then
        return 1  # Assume not rate limited if unknown
    fi
    
    # Consider rate limited if less than 10 pulls remaining
    if [[ $remaining -lt 10 ]]; then
        return 0
    fi
    
    return 1
}

has_docker_hub_auth() {
    local config_file="$HOME/.docker/config.json"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    grep -q '"https://index.docker.io/v1/"\|"https://index.docker.io/v1"\|"docker.io"\|"registry-1.docker.io"' "$config_file" 2>/dev/null
}

# Format rate limit status for display
format_rate_limit_status() {
    local limit_data=$(check_docker_hub_limits)
    
    declare -A data
    while IFS='=' read -r key value; do
        data[$key]="$value"
    done <<< "$limit_data"
    
    local status="${data[STATUS]}"
    local remaining="${data[REMAINING]}"
    local limit="${data[LIMIT]}"
    local message="${data[MESSAGE]}"
    
    case "$status" in
        critical)
            echo -e "${RED}⚠${NC}  Rate Limit: ${RED}CRITICAL${NC} - $message"
            echo "   Consider authenticating or enabling registry cache"
            ;;
        warning)
            echo -e "${YELLOW}⚠${NC}  Rate Limit: ${YELLOW}WARNING${NC} - $message"
            echo "   Registry cache will help avoid hitting the limit"
            ;;
        ok)
            echo -e "${GREEN}✓${NC}  Rate Limit: ${GREEN}OK${NC} - $message"
            ;;
        authenticated)
            echo -e "${GREEN}✓${NC}  Docker Hub: ${GREEN}Authenticated${NC} - $message"
            ;;
        anonymous)
            echo -e "${YELLOW}⚠${NC}  Docker Hub: ${YELLOW}Anonymous${NC} - $message"
            echo "   Authenticating doubles your limit to 200/6hr"
            ;;
        *)
            echo "  Rate Limit: Status unknown"
            ;;
    esac
}

# Prompt for Docker Hub authentication with context
prompt_hub_auth_contextual() {
    local image_count="${1:-0}"
    
    echo ""
    log_step "Docker Hub Authentication (Optional)"
    echo ""
    echo "Your setup requires approximately $image_count Docker Hub images."
    echo ""
    echo "Benefits of authenticating:"
    echo "  • Increases rate limit from 100 to 200 pulls per 6 hours"
    echo "  • Recommended if pulling many images"
    echo "  • Free Docker Hub account works fine"
    echo ""
    
    format_rate_limit_status
    echo ""
    
    # Check if already at risk
    if is_rate_limited; then
        log_warn "You are close to or at the rate limit!"
        echo "Authentication is strongly recommended."
        echo ""
        
        if prompt_yes_no "Authenticate with Docker Hub now?" "y"; then
            return 0
        else
            return 1
        fi
    fi
    
    # Offer quick auth with timeout
    if prompt_yes_no "Authenticate with Docker Hub now?" "n"; then
        return 0
    fi
    
    return 1
}

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

    # Validate any stored GHCR credential — a bad/expired token causes "denied"
    # on ALL ghcr.io pulls, even public images. Clear it if it's stale.
    if grep -q '"ghcr.io"' "$HOME/.docker/config.json" 2>/dev/null; then
        local _test_response
        _test_response=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $(cat "$HOME/.docker/config.json" | \
                python3 -c "import sys,json,base64; \
                    d=json.load(sys.stdin); \
                    auth=d.get('auths',{}).get('ghcr.io',{}).get('auth',''); \
                    print(base64.b64decode(auth).decode().split(':',1)[1] if auth else '')" 2>/dev/null)" \
            "https://ghcr.io/v2/" 2>/dev/null)
        if [[ "$_test_response" == "401" || "$_test_response" == "403" ]]; then
            log_warn "Stored GHCR credential is expired or invalid — clearing it"
            docker logout ghcr.io &>/dev/null || true
        else
            log_info "Already authenticated with GitHub Container Registry"
            return 0
        fi
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
    echo "  Authenticated registries:"

    if grep -q "docker.io\|https://index.docker.io" "$config_file" 2>/dev/null; then
        log_success "Docker Hub (docker.io)"
    fi

    if grep -q "ghcr.io" "$config_file" 2>/dev/null; then
        log_success "GitHub Container Registry (ghcr.io)"
    fi

    if grep -q "gcr.io" "$config_file" 2>/dev/null; then
        log_success "Google Container Registry (gcr.io)"
    fi

    echo ""
}

# Export functions
export -f docker_login_hub docker_login_ghcr docker_login_gcr docker_login_private
export -f setup_docker_auth check_docker_auth_status
