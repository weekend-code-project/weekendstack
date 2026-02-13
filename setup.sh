#!/bin/bash
# WeekendStack Interactive Setup Script
# Automated deployment with interactive customization

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Load library functions
for lib in "$SCRIPT_DIR/tools/setup/lib"/*.sh; do
    if [[ -f "$lib" ]]; then
        source "$lib"
    fi
done

# Version
VERSION="1.0.0"

# Global flags
SETUP_MODE="interactive"  # interactive or quick
SKIP_AUTH=false
SKIP_PULL=false
SKIP_CLOUDFLARE=false
SKIP_CERTS=false
DRY_RUN=false

# Show usage
show_usage() {
    cat << EOF
WeekendStack Setup Script v$VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --version           Show version information
    -q, --quick             Quick setup with defaults (non-interactive)
    -i, --interactive       Interactive setup (default)
    --skip-auth             Skip Docker registry authentication
    --skip-pull             Skip image pulling
    --skip-cloudflare       Skip Cloudflare Tunnel setup
    --skip-certs            Skip certificate generation
    --dry-run               Show what would be done without executing
    --validate              Validate configuration without starting services
    --status                Show current deployment status
    --rollback              Restore previous .env from backup
    --start                 Start the stack after setup
    --stop                  Stop all services
    --restart               Restart all services

EXAMPLES:
    # Interactive setup (recommended for first-time)
    $0

    # Quick setup with defaults
    $0 --quick

    # Setup without Cloudflare
    $0 --skip-cloudflare

    # Validate configuration
    $0 --validate

    # Start services
    $0 --start

DOCUMENTATION:
    See docs/setup-script-guide.md for detailed instructions
    See SETUP_SUMMARY.md (after setup) for service URLs and credentials

EOF
}

# Show version
show_version() {
    echo "WeekendStack Setup Script v$VERSION"
    echo "Copyright © 2026 WeekendStack Project"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -q|--quick)
                SETUP_MODE="quick"
                shift
                ;;
            -i|--interactive)
                SETUP_MODE="interactive"
                shift
                ;;
            --skip-auth)
                SKIP_AUTH=true
                shift
                ;;
            --skip-pull)
                SKIP_PULL=true
                shift
                ;;
            --skip-cloudflare)
                SKIP_CLOUDFLARE=true
                shift
                ;;
            --skip-certs)
                SKIP_CERTS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --validate)
                validate_configuration
                exit $?
                ;;
            --status)
                show_deployment_status
                exit $?
                ;;
            --rollback)
                rollback_configuration
                exit $?
                ;;
            --start)
                start_services
                exit $?
                ;;
            --stop)
                stop_services
                exit $?
                ;;
            --restart)
                restart_services
                exit $?
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_header "Prerequisites Check"
    
    local errors=0
    
    # Check Docker
    if ! check_command docker; then
        log_error "Docker is not installed"
        echo "Install Docker: https://docs.docker.com/get-docker/"
        errors=$((errors + 1))
    else
        local docker_version=$(docker --version | grep -oP '\d+\.\d+' | head -n1)
        log_success "Docker installed: v$docker_version"
    fi
    
    # Check Docker Compose
    if ! check_command docker compose version; then
        log_error "Docker Compose V2 is not available"
        echo "Ensure Docker Compose V2 is installed (docker compose)"
        errors=$((errors + 1))
    else
        local compose_version=$(docker compose version --short)
        log_success "Docker Compose installed: v$compose_version"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        echo "Start Docker daemon: sudo systemctl start docker"
        errors=$((errors + 1))
    else
        log_success "Docker daemon: running"
    fi
    
    # Check user permissions
    if ! docker ps >/dev/null 2>&1; then
        log_warn "Current user may not have Docker permissions"
        echo "Add user to docker group: sudo usermod -aG docker \$USER"
    fi
    
    # Check disk space (need at least 50GB)
    local available_disk=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if ((available_disk < 50)); then
        log_warn "Low disk space: ${available_disk}GB available (recommended: 50GB+)"
    else
        log_success "Disk space: ${available_disk}GB available"
    fi
    
    # Check memory (need at least 8GB)
    if check_command free; then
        local total_memory=$(free -g | awk '/^Mem:/{print $2}')
        if ((total_memory < 8)); then
            log_warn "Low memory: ${total_memory}GB (recommended: 8GB+)"
        else
            log_success "Memory: ${total_memory}GB available"
        fi
    fi
    
    # Check for GPU (informational)
    if check_command nvidia-smi; then
        log_success "NVIDIA GPU detected"
        export GPU_AVAILABLE=true
    else
        log_info "No NVIDIA GPU detected (AI services will use CPU)"
        export GPU_AVAILABLE=false
    fi
    
    if ((errors > 0)); then
        log_error "Prerequisites check failed with $errors errors"
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

# Show welcome banner
show_welcome() {
    clear
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║                                                                  ║${NC}"
    echo "${CYAN}║${NC}        ${BOLD}WeekendStack Interactive Setup Script v$VERSION${NC}         ${CYAN}║${NC}"
    echo "${CYAN}║                                                                  ║${NC}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This script will help you set up your self-hosted infrastructure with:"
    echo ""
    echo "  • 65+ open-source services across 9 categories"
    echo "  • Local HTTPS with automatic certificate generation"
    echo "  • Optional Cloudflare Tunnel for external access"
    echo "  • Secure credential generation"
    echo "  • Profile-based deployment (AI, Dev, Productivity, etc.)"
    echo ""
    
    if [[ "$SETUP_MODE" == "quick" ]]; then
        echo "Running in ${BOLD}QUICK MODE${NC} - using defaults where possible"
    else
        echo "Running in ${BOLD}INTERACTIVE MODE${NC} - you can customize all settings"
    fi
    
    echo ""
    echo "Estimated time: 5-15 minutes"
    echo "Requirements: 8GB+ RAM, 50GB+ disk space, Docker installed"
    echo ""
    
    if ! $DRY_RUN; then
        if ! prompt_yes_no "Continue with setup?" "y"; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi
}

# Main setup workflow
main_setup() {
    log_header "WeekendStack Setup Starting"
    
    # 1. Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed. Please fix errors and try again."
        exit 1
    fi
    
    # 2. Select profiles
    local selected_profiles=()
    if [[ "$SETUP_MODE" == "quick" ]]; then
        selected_profiles=($(select_profiles_quick))
    else
        selected_profiles=($(select_profiles_interactive))
    fi
    
    export SELECTED_PROFILES=("${selected_profiles[@]}")
    
    # 3. Check system resources
    local resources=($(estimate_resources "${selected_profiles[@]}"))
    local required_memory=${resources[0]}
    local required_disk=${resources[1]}
    
    if ! check_system_resources "$required_memory" "$required_disk"; then
        log_error "Insufficient system resources"
        exit 1
    fi
    
    # 4. Docker registry authentication
    if ! $SKIP_AUTH; then
        if [[ "$SETUP_MODE" == "quick" ]]; then
            log_info "Skipping Docker authentication in quick mode (use --interactive for auth)"
        else
            setup_docker_auth || log_warn "Docker authentication failed or skipped"
        fi
    fi
    
    # 5. Generate environment configuration
    if [[ "$SETUP_MODE" == "quick" ]]; then
        generate_env_quick "${selected_profiles[@]}"
    else
        generate_env_interactive "${selected_profiles[@]}"
    fi
    
    # 6. Validate .env file
    log_step "Validating environment configuration..."
    if ! "$SCRIPT_DIR/tools/validate-env.sh" 2>&1 | grep -q "All checks passed"; then
        log_warn "Environment validation found issues"
        if [[ "$SETUP_MODE" == "interactive" ]]; then
            if ! prompt_yes_no "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    else
        log_success "Environment validation passed"
    fi
    
    # 7. Create directories
    setup_all_directories "${selected_profiles[@]}"
    
    # 8. Create Docker networks
    create_docker_networks
    
    # 9. Create Docker volumes
    create_docker_volumes
    
    # 10. Certificate setup
    if ! $SKIP_CERTS; then
        setup_certificates || log_warn "Certificate setup incomplete"
    fi
    
    # 11. Cloudflare Tunnel setup
    if ! $SKIP_CLOUDFLARE && [[ "$SETUP_MODE" == "interactive" ]]; then
        setup_cloudflare_tunnel || log_warn "Cloudflare Tunnel setup skipped"
    fi
    
    # 12. Pull Docker images
    if ! $SKIP_PULL; then
        pull_images "${selected_profiles[@]}"
    fi
    
    # 13. Run init containers
    local init_containers=($(get_init_containers_for_profiles "${selected_profiles[@]}"))
    if [[ ${#init_containers[@]} -gt 0 ]]; then
        run_init_containers "${init_containers[@]}"
    fi
    
    # 14. Generate setup summary
    generate_setup_summary "${selected_profiles[@]}"
    
    # 15. Ask to start services
    echo ""
    if prompt_yes_no "Start WeekendStack services now?" "y"; then
        start_services_with_profiles "${selected_profiles[@]}"
        display_summary_to_console
    else
        log_info "Services not started. Run './setup.sh --start' when ready."
        echo ""
        echo "To start services later:"
        echo "  docker compose up -d"
        echo ""
    fi
    
    log_success "Setup complete! See SETUP_SUMMARY.md for details."
}

# Pull Docker images
pull_images() {
    local profiles=("$@")
    
    log_header "Pulling Docker Images"
    
    echo "This may take several minutes depending on your internet connection..."
    echo ""
    
    local profile_args=""
    for profile in "${profiles[@]}"; do
        profile_args="$profile_args --profile $profile"
    done
    
    log_step "Pulling images for profiles: ${profiles[*]}"
    
    if docker compose $profile_args pull 2>&1 | tee /tmp/docker-pull.log; then
        log_success "All images pulled successfully"
    else
        log_warn "Some images may have failed to pull (check /tmp/docker-pull.log)"
        if ! prompt_yes_no "Continue anyway?" "y"; then
            exit 1
        fi
    fi
}

# Start services with profiles
start_services_with_profiles() {
    local profiles=("$@")
    
    log_header "Starting Services"
    
    local profile_args=""
    for profile in "${profiles[@]}"; do
        profile_args="$profile_args --profile $profile"
    done
    
    log_step "Starting services for profiles: ${profiles[*]}"
    
    if docker compose $profile_args up -d; then
        log_success "Services started successfully"
        
        echo ""
        log_info "Waiting for services to become healthy..."
        sleep 5
        
        # Show running services
        echo ""
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    else
        log_error "Failed to start services"
        exit 1
    fi
}

# Validate configuration
validate_configuration() {
    log_header "Configuration Validation"
    
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_error ".env file not found. Run setup first."
        return 1
    fi
    
    # Run validate-env.sh
    "$SCRIPT_DIR/tools/validate-env.sh"
    
    # Check compose files
    log_step "Validating docker-compose files..."
    if docker compose config >/dev/null 2>&1; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration has errors"
        return 1
    fi
    
    return 0
}

# Show deployment status
show_deployment_status() {
    log_header "Deployment Status"
    
    # Check if .env exists
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_warn "Not configured - run setup first"
        return 1
    fi
    
    # Show setup metadata
    if grep -q "SETUP_COMPLETED=true" "$SCRIPT_DIR/.env"; then
        local setup_date=$(grep "^SETUP_DATE=" "$SCRIPT_DIR/.env" | cut -d'=' -f2)
        local profiles=$(grep "^SELECTED_PROFILES=" "$SCRIPT_DIR/.env" | cut -d'=' -f2)
        
        echo "Setup completed: $setup_date"
        echo "Active profiles: $profiles"
        echo ""
    fi
    
    # Show running services
    log_step "Running services:"
    docker compose ps
    
    echo ""
    
    # Show resource usage
    log_step "Resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    return 0
}

# Rollback configuration
rollback_configuration() {
    log_header "Configuration Rollback"
    
    local backup_dir="$SCRIPT_DIR/_trash"
    local latest_backup=$(ls -t "$backup_dir"/.env.backup.* 2>/dev/null | head -n1)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No .env backup found in $backup_dir"
        return 1
    fi
    
    log_info "Latest backup: $latest_backup"
    
    if prompt_yes_no "Restore this backup?" "y"; then
        cp "$latest_backup" "$SCRIPT_DIR/.env"
        log_success "Configuration restored from backup"
        log_info "Restart services: ./setup.sh --restart"
    else
        log_info "Rollback cancelled"
    fi
    
    return 0
}

# Start services
start_services() {
    log_header "Starting Services"
    
    if docker compose up -d; then
        log_success "Services started"
        docker compose ps
    else
        log_error "Failed to start services"
        return 1
    fi
}

# Stop services
stop_services() {
    log_header "Stopping Services"
    
    if docker compose down; then
        log_success "Services stopped"
    else
        log_error "Failed to stop services"
        return 1
    fi
}

# Restart services
restart_services() {
    log_header "Restarting Services"
    
    if docker compose restart; then
        log_success "Services restarted"
        docker compose ps
    else
        log_error "Failed to restart services"
        return 1
    fi
}

# Main entry point
main() {
    parse_args "$@"
    
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    if $DRY_RUN; then
        log_info "DRY RUN MODE - No changes will be made"
        SETUP_MODE="interactive"
    fi
    
    show_welcome
    main_setup
}

# Run main function
main "$@"
