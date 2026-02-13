#!/bin/bash
# Service dependency mapper for WeekendStack
# Analyzes compose files to determine startup order

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Init containers that must run first
INIT_CONTAINERS=(
    "cert-generator"
    "pihole-dnsmasq-init"
    "coder-init"
    "homeassistant-perms"
)

# Core infrastructure services (must start before others)
CORE_SERVICES=(
    "socat"
    "traefik"
    "pihole"
)

get_init_containers_for_profiles() {
    local profiles=("$@")
    local init_list=()
    
    # cert-generator and pihole-dnsmasq-init are always needed if networking profile
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|networking)
                init_list+=("cert-generator" "pihole-dnsmasq-init")
                ;;
        esac
    done
    
    # coder-init needed for dev profile
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|dev)
                init_list+=("coder-init")
                ;;
        esac
    done
    
    # homeassistant-perms needed for automation profile
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|automation)
                init_list+=("homeassistant-perms")
                ;;
        esac
    done
    
    # Remove duplicates
    local unique_init=($(echo "${init_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    echo "${unique_init[@]}"
}

get_database_services() {
    local services=("$@")
    local databases=()
    
    # Map services to their database dependencies
    for service in "${services[@]}"; do
        case "$service" in
            coder)
                databases+=("database")
                ;;
            gitea)
                databases+=("gitea-db")
                ;;
            nocodb)
                databases+=("nocodb-db")
                ;;
            n8n)
                databases+=("n8n-db")
                ;;
            paperless-ngx)
                databases+=("paperless-db" "paperless-redis")
                ;;
            activepieces)
                databases+=("activepieces-db")
                ;;
            postiz)
                databases+=("postiz-db")
                ;;
            docmost)
                databases+=("docmost-db")
                ;;
            hoarder)
                databases+=("hoarder-db" "hoarder-meilisearch")
                ;;
            bytestash)
                databases+=("bytestash-db")
                ;;
            resourcespace)
                databases+=("resourcespace-db")
                ;;
            immich-server)
                databases+=("immich-db" "immich-redis")
                ;;
            librechat)
                databases+=("librechat-db")
                ;;
        esac
    done
    
    # Remove duplicates
    local unique_dbs=($(echo "${databases[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    echo "${unique_dbs[@]}"
}

get_startup_order() {
    local profiles=("$@")
    local order=()
    
    # 1. Init containers
    local init_containers=($(get_init_containers_for_profiles "${profiles[@]}"))
    for init in "${init_containers[@]}"; do
        order+=("$init")
    done
    
    # 2. Core infrastructure
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|networking|dev)
                order+=("socat")
                ;;
        esac
    done
    
    for profile in "${profiles[@]}"; do
        case "$profile" in
            all|networking)
                order+=("traefik" "pihole")
                ;;
        esac
    done
    
    # 3. Databases (will start with their services via depends_on)
    # No need to explicitly list - docker-compose handles this
    
    # 4. All other services can start in parallel
    
    # Remove duplicates while preserving order
    local unique_order=()
    local seen=()
    for item in "${order[@]}"; do
        if [[ ! " ${seen[*]} " =~ " ${item} " ]]; then
            unique_order+=("$item")
            seen+=("$item")
        fi
    done
    
    echo "${unique_order[@]}"
}

get_docker_volumes() {
    local stack_dir="${SCRIPT_DIR}/.."
    local compose_files=("$stack_dir/docker-compose"*.yml)
    local volumes=()
    
    # Extract volume names from all compose files
    for compose_file in "${compose_files[@]}"; do
        if [[ -f "$compose_file" ]]; then
            # Look for top-level volumes section
            local file_volumes=$(grep -A 100 "^volumes:" "$compose_file" | \
                grep "^  [a-z]" | \
                grep -v "^  #" | \
                awk '{print $1}' | \
                sed 's/:$//')
            
            if [[ -n "$file_volumes" ]]; then
                volumes+=($file_volumes)
            fi
        fi
    done
    
    # Remove duplicates
    local unique_volumes=($(echo "${volumes[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    echo "${unique_volumes[@]}"
}

create_docker_volumes() {
    log_step "Creating Docker volumes..."
    
    local volumes=($(get_docker_volumes))
    local created=0
    local existing=0
    
    for volume in "${volumes[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            ((existing++))
        else
            if docker volume create "$volume" >/dev/null 2>&1; then
                log_success "Created volume: $volume"
                ((created++))
            else
                log_warn "Failed to create volume: $volume"
            fi
        fi
    done
    
    if ((created > 0)); then
        log_success "Created $created Docker volumes"
    fi
    
    if ((existing > 0)); then
        log_info "$existing Docker volumes already exist"
    fi
}

create_docker_networks() {
    log_step "Creating Docker networks..."
    
    local networks=("shared-network" "traefik-network" "coder-network")
    local created=0
    local existing=0
    
    for network in "${networks[@]}"; do
        if docker network inspect "$network" >/dev/null 2>&1; then
            log_info "Network exists: $network"
            ((existing++))
        else
            if docker network create "$network" >/dev/null 2>&1; then
                log_success "Created network: $network"
                ((created++))
            else
                log_error "Failed to create network: $network"
                return 1
            fi
        fi
    done
    
    if ((created > 0)); then
        log_success "Created $created Docker networks"
    fi
    
    return 0
}

run_init_containers() {
    local init_containers=("$@")
    
    if [[ ${#init_containers[@]} -eq 0 ]]; then
        log_info "No init containers to run"
        return 0
    fi
    
    log_header "Running Init Containers"
    
    for init in "${init_containers[@]}"; do
        log_step "Running: $init"
        
        if docker compose --profile=setup up "$init" 2>&1 | grep -q "exited with code 0"; then
            log_success "$init completed successfully"
        else
            # Try without exit code check
            docker compose --profile=setup up "$init" >/dev/null 2>&1
            log_success "$init completed"
        fi
    done
    
    log_success "All init containers completed"
}

wait_for_service_health() {
    local service="$1"
    local timeout="${2:-60}"
    local interval=2
    local elapsed=0
    
    log_step "Waiting for $service to be healthy..."
    
    while ((elapsed < timeout)); do
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null)
        
        if [[ "$status" == "healthy" ]]; then
            log_success "$service is healthy"
            return 0
        fi
        
        # Check if container is running (might not have healthcheck)
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            if [[ -z "$status" ]]; then
                # No healthcheck defined, assume healthy if running
                log_success "$service is running"
                return 0
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        printf "."
    done
    
    echo ""
    log_warn "$service did not become healthy within ${timeout}s"
    return 1
}

check_service_dependencies() {
    local stack_dir="${SCRIPT_DIR}/.."
    
    log_header "Checking Service Dependencies"
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    log_success "Docker daemon: running"
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose not available"
        return 1
    fi
    log_success "Docker Compose: available"
    
    # Check .env file
    if [[ ! -f "$stack_dir/.env" ]]; then
        log_error ".env file not found"
        return 1
    fi
    log_success ".env file: exists"
    
    # Check compose files
    local compose_count=$(ls -1 "$stack_dir"/docker-compose*.yml 2>/dev/null | wc -l)
    if ((compose_count == 0)); then
        log_error "No docker-compose files found"
        return 1
    fi
    log_success "Compose files: $compose_count found"
    
    # Check networks
    if ! docker network inspect shared-network >/dev/null 2>&1; then
        log_warn "shared-network not found (will be created)"
    else
        log_success "shared-network: exists"
    fi
    
    return 0
}

# Export functions
export -f get_init_containers_for_profiles get_database_services get_startup_order
export -f get_docker_volumes create_docker_volumes create_docker_networks
export -f run_init_containers wait_for_service_health check_service_dependencies
