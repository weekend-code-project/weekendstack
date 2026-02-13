#!/bin/bash
# WeekendStack Uninstall Script
# Safely remove WeekendStack services and optionally clean up data

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
if [[ -f "$SCRIPT_DIR/tools/setup/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/tools/setup/lib/common.sh"
else
    # Minimal functions if library not available
    log_error() { echo "ERROR: $*" >&2; }
    log_warn() { echo "WARNING: $*"; }
    log_info() { echo "INFO: $*"; }
    log_success() { echo "SUCCESS: $*"; }
    log_header() { echo ""; echo "=== $* ==="; echo ""; }
    prompt_yes_no() { read -r -p "$1 [y/N]: " response; [[ "$response" =~ ^[Yy]$ ]]; }
fi

VERSION="1.0.0"

show_usage() {
    cat << EOF
WeekendStack Uninstall Script v$VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    --remove-volumes        Remove Docker volumes (CAUTION: deletes databases)
    --remove-files          Remove user files directory (CAUTION: deletes documents/photos)
    --remove-config         Remove configuration directory
    --full-cleanup          Remove everything (use with extreme caution!)
    --keep-backups          Keep .env backups in _trash/
    --profiles PROFILES     Only remove services from specific profiles

SAFETY FEATURES:
    • Always backs up .env before removal
    • Never deletes user files by default
    • Prompts for confirmation on destructive operations
    • Creates a removal summary

EXAMPLES:
    # Stop services only (safest)
    $0

    # Remove services and Docker volumes (keeps user files)
    $0 --remove-volumes

    # Remove specific profiles
    $0 --profiles dev,ai

    # Complete removal (DANGER!)
    $0 --full-cleanup

CAUTION:
    --remove-files will DELETE all your documents, photos, and media!
    Make sure you have backups before using this option.

EOF
}

# Parse arguments
REMOVE_VOLUMES=false
REMOVE_FILES=false
REMOVE_CONFIG=false
FULL_CLEANUP=false
KEEP_BACKUPS=true
SPECIFIC_PROFILES=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --remove-volumes)
                REMOVE_VOLUMES=true
                shift
                ;;
            --remove-files)
                REMOVE_FILES=true
                shift
                ;;
            --remove-config)
                REMOVE_CONFIG=true
                shift
                ;;
            --full-cleanup)
                FULL_CLEANUP=true
                REMOVE_VOLUMES=true
                REMOVE_FILES=true
                REMOVE_CONFIG=true
                shift
                ;;
            --keep-backups)
                KEEP_BACKUPS=true
                shift
                ;;
            --profiles)
                SPECIFIC_PROFILES="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
    done
}

show_warning_banner() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                    ║"
    echo "║                  WeekendStack Uninstall Script                     ║"
    echo "║                                                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if $FULL_CLEANUP; then
        echo "⚠️  WARNING: FULL CLEANUP MODE ⚠️"
        echo ""
        echo "This will remove:"
        echo "  • All Docker containers"
        echo "  • All Docker volumes (databases)"
        echo "  • All user files (documents, photos, media)"
        echo "  • All configuration files"
        echo ""
        echo "THIS CANNOT BE UNDONE!"
        echo ""
    else
        echo "This will:"
        echo "  • Stop all WeekendStack services"
        
        if $REMOVE_VOLUMES; then
            echo "  • Remove Docker volumes (databases)"
        fi
        
        if $REMOVE_FILES; then
            echo "  • Remove user files directory"
        fi
        
        if $REMOVE_CONFIG; then
            echo "  • Remove configuration directory"
        fi
        
        echo ""
        echo "This will NOT remove:"
        
        if ! $REMOVE_FILES; then
            echo "  • User files (./files/)"
        fi
        
        if ! $REMOVE_CONFIG; then
            echo "  • Configuration files (./config/)"
        fi
        
        if ! $REMOVE_VOLUMES; then
            echo "  • Docker volumes"
        fi
    fi
    
    echo ""
}

stop_services() {
    log_header "Stopping Services"
    
    cd "$SCRIPT_DIR"
    
    if [[ -n "$SPECIFIC_PROFILES" ]]; then
        log_info "Stopping services for profiles: $SPECIFIC_PROFILES"
        IFS=',' read -ra PROFILES <<< "$SPECIFIC_PROFILES"
        local profile_args=""
        for profile in "${PROFILES[@]}"; do
            profile_args="$profile_args --profile $profile"
        done
        docker compose $profile_args down
    else
        log_info "Stopping all services..."
        docker compose down
    fi
    
    log_success "Services stopped"
}

remove_containers() {
    log_header "Removing Containers"
    
    cd "$SCRIPT_DIR"
    
    # Force remove all containers from this stack
    local containers=$(docker compose ps -aq)
    
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs docker rm -f 2>/dev/null || true
        log_success "Containers removed"
    else
        log_info "No containers to remove"
    fi
}

remove_volumes() {
    if ! $REMOVE_VOLUMES; then
        log_info "Skipping Docker volume removal (use --remove-volumes to remove)"
        return 0
    fi
    
    log_header "Removing Docker Volumes"
    
    log_warn "This will DELETE all databases and application data!"
    echo ""
    
    if ! prompt_yes_no "Are you sure you want to remove Docker volumes?"; then
        log_info "Skipping volume removal"
        return 0
    fi
    
    # Get list of volumes from compose files
    local volumes=$(docker volume ls --format '{{.Name}}' | grep -E 'coder|gitea|nocodb|paperless|immich|mealie|firefly' || true)
    
    if [[ -n "$volumes" ]]; then
        echo "Volumes to be removed:"
        echo "$volumes"
        echo ""
        
        if prompt_yes_no "Proceed with volume removal?"; then
            echo "$volumes" | xargs docker volume rm 2>/dev/null || true
            log_success "Volumes removed"
        else
            log_info "Volume removal cancelled"
        fi
    else
        log_info "No matching volumes found"
    fi
}

remove_networks() {
    log_header "Removing Docker Networks"
    
    local networks=("shared-network" "traefik-network" "coder-network")
    local removed=0
    
    for network in "${networks[@]}"; do
        if docker network inspect "$network" >/dev/null 2>&1; then
            if docker network rm "$network" 2>/dev/null; then
                log_success "Removed network: $network"
                removed=$((removed + 1))
            else
                log_warn "Could not remove network: $network (may be in use)"
            fi
        fi
    done
    
    if ((removed == 0)); then
        log_info "No networks to remove"
    fi
}

remove_files() {
    if ! $REMOVE_FILES; then
        log_info "Skipping user files removal (use --remove-files to remove)"
        return 0
    fi
    
    log_header "Removing User Files"
    
    local files_dir="$SCRIPT_DIR/files"
    
    if [[ ! -d "$files_dir" ]]; then
        log_info "Files directory does not exist"
        return 0
    fi
    
    log_warn "⚠️  DANGER: This will DELETE all your documents, photos, and media!"
    echo ""
    echo "Files directory: $files_dir"
    echo ""
    du -sh "$files_dir" 2>/dev/null || echo "Size: unknown"
    echo ""
    
    if ! prompt_yes_no "Are you ABSOLUTELY SURE you want to delete all user files?"; then
        log_info "File removal cancelled"
        return 0
    fi
    
    echo ""
    log_warn "Last chance! Type 'DELETE' to confirm:"
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "File removal cancelled"
        return 0
    fi
    
    rm -rf "$files_dir"
    log_success "User files removed"
}

remove_config() {
    if ! $REMOVE_CONFIG; then
        log_info "Skipping configuration removal (use --remove-config to remove)"
        return 0
    fi
    
    log_header "Removing Configuration"
    
    local config_dir="$SCRIPT_DIR/config"
    
    if [[ ! -d "$config_dir" ]]; then
        log_info "Config directory does not exist"
        return 0
    fi
    
    log_warn "This will delete all configuration files including:"
    echo "  • Traefik certificates"
    echo "  • Cloudflare tunnel credentials"
    echo "  • SSH keys"
    echo "  • Service configurations"
    echo ""
    
    if ! prompt_yes_no "Remove configuration directory?"; then
        log_info "Config removal cancelled"
        return 0
    fi
    
    # Backup important files first
    if [[ $KEEP_BACKUPS ]]; then
        local backup_dir="$SCRIPT_DIR/_trash/config-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Backup certificates
        if [[ -d "$config_dir/traefik/certs" ]]; then
            cp -r "$config_dir/traefik/certs" "$backup_dir/" || true
        fi
        
        # Backup Cloudflare credentials
        if [[ -d "$config_dir/cloudflare" ]]; then
            cp -r "$config_dir/cloudflare" "$backup_dir/" || true
        fi
        
        log_info "Backed up important config to: $backup_dir"
    fi
    
    rm -rf "$config_dir"
    log_success "Configuration removed"
}

backup_env() {
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        local timestamp=$(date +%Y%m%d-%H%M%S)
        local backup_dir="$SCRIPT_DIR/_trash"
        mkdir -p "$backup_dir"
        
        cp "$SCRIPT_DIR/.env" "$backup_dir/.env.backup.$timestamp"
        log_success "Backed up .env to: $backup_dir/.env.backup.$timestamp"
    fi
}

remove_env() {
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        if prompt_yes_no "Remove .env file?"; then
            rm "$SCRIPT_DIR/.env"
            log_success "Removed .env file"
        else
            log_info "Kept .env file"
        fi
    fi
}

generate_removal_summary() {
    local summary_file="$SCRIPT_DIR/UNINSTALL_SUMMARY.md"
    
    cat > "$summary_file" << EOF
# WeekendStack Uninstall Summary

**Uninstall completed:** $(date +"%Y-%m-%d %H:%M:%S")

## What Was Removed

EOF
    
    echo "- ✓ Docker containers stopped and removed" >> "$summary_file"
    
    if $REMOVE_VOLUMES; then
        echo "- ✓ Docker volumes removed (databases deleted)" >> "$summary_file"
    else
        echo "- ✗ Docker volumes kept (databases preserved)" >> "$summary_file"
    fi
    
    if $REMOVE_FILES; then
        echo "- ✓ User files directory removed" >> "$summary_file"
    else
        echo "- ✗ User files directory kept (./files/)" >> "$summary_file"
    fi
    
    if $REMOVE_CONFIG; then
        echo "- ✓ Configuration directory removed" >> "$summary_file"
    else
        echo "- ✗ Configuration directory kept (./config/)" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

## Backups

All .env backups are in: \`_trash/\`

EOF
    
    if $REMOVE_CONFIG && $KEEP_BACKUPS; then
        local latest_backup=$(ls -t "$SCRIPT_DIR/_trash"/config-backup-* 2>/dev/null | head -n1)
        if [[ -n "$latest_backup" ]]; then
            echo "Configuration backup: \`$latest_backup\`" >> "$summary_file"
        fi
    fi
    
    cat >> "$summary_file" << EOF

## Reinstallation

To reinstall WeekendStack:

\`\`\`bash
./setup.sh
\`\`\`

## What Remains

EOF
    
    if ! $REMOVE_FILES; then
        echo "- User files: \`./files/\`" >> "$summary_file"
    fi
    
    if ! $REMOVE_CONFIG; then
        echo "- Configuration: \`./config/\`" >> "$summary_file"
    fi
    
    echo "- Docker Compose files: \`./docker-compose*.yml\`" >> "$summary_file"
    echo "- Documentation: \`./docs/\`" >> "$summary_file"
    echo "- Scripts: \`./tools/\`" >> "$summary_file"
    
    log_success "Removal summary saved to: $summary_file"
}

main() {
    parse_args "$@"
    
    cd "$SCRIPT_DIR"
    
    show_warning_banner
    
    if ! prompt_yes_no "Proceed with uninstall?"; then
        log_info "Uninstall cancelled"
        exit 0
    fi
    
    echo ""
    
    # Backup .env before any removal
    backup_env
    
    # Stop and remove containers
    stop_services
    remove_containers
    
    # Remove volumes if requested
    remove_volumes
    
    # Remove networks
    remove_networks
    
    # Remove files if requested
    remove_files
    
    # Remove config if requested
    remove_config
    
    # Remove .env
    remove_env
    
    # Generate summary
    generate_removal_summary
    
    echo ""
    log_success "Uninstall complete!"
    echo ""
    echo "See UNINSTALL_SUMMARY.md for details"
    echo ""
}

main "$@"
