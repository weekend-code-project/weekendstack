#!/bin/bash
# WeekendStack Uninstall Script
# Multi-level cleanup with interactive selection

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Load common functions
if [[ -f "$SCRIPT_DIR/tools/setup/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/tools/setup/lib/common.sh"
else
    # Minimal functions if library not available
    log_error() { echo -e "${RED}ERROR: $*${NC}" >&2; }
    log_warn() { echo -e "${YELLOW}WARNING: $*${NC}"; }
    log_info() { echo -e "${BLUE}INFO: $*${NC}"; }
    log_success() { echo -e "${GREEN}SUCCESS: $*${NC}"; }
    log_header() { echo ""; echo -e "${CYAN}${BOLD}=== $* ===${NC}"; echo ""; }
    prompt_yes_no() { read -r -p "$1 [y/N]: " response; [[ "$response" =~ ^[Yy]$ ]]; }
fi

VERSION="2.0.0"

show_usage() {
    echo -e "${BOLD}WeekendStack Uninstall Script v$VERSION${NC}"
    echo ""
    echo "USAGE:"
    echo "    $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "    -h, --help              Show this help message"
    echo "    -l, --level LEVEL       Cleanup level (1, 2, or 3)"
    echo "    --non-interactive       Use specified level without prompts"
    echo ""
    echo "CLEANUP LEVELS:"
    echo -e "    ${GREEN}Level 1${NC} - Quick Reset (soft reset)"
    echo "      • Stop and remove all containers"
    echo "      • Remove .env, docker-compose.custom.yml, SETUP_SUMMARY.md"
    echo "      • Remove all Docker volumes (deletes databases)"
    echo "      • Remove all Docker networks"
    echo "      • Keep: Docker images, data/, files/, config/"
    echo ""
    echo -e "    ${YELLOW}Level 2${NC} - Full Reset (re-staging)"
    echo "      • Everything from Level 1"
    echo "      • Remove data/ directory (application state)"
    echo "      • Remove files/ directory (your documents/photos)"
    echo "      • Remove config/ directory (certificates/settings)"
    echo "      • Keep: Docker images (no re-download needed)"
    echo ""
    echo -e "    ${RED}Level 3${NC} - Complete Cleanup (nuclear)"
    echo "      • Everything from Level 2"
    echo "      • Remove all Docker images (will need to re-download)"
    echo "      • Nothing is kept"
    echo ""
    echo "EXAMPLES:"
    echo "    # Interactive mode (default - prompts for level)"
    echo "    $0"
    echo ""
    echo "    # Quick reset to Level 1 (no prompts)"
    echo "    $0 --level 1 --non-interactive"
    echo ""
    echo "    # Full reset to Level 2"
    echo "    $0 --level 2"
    echo ""
    echo "    # Complete cleanup (DANGER!)"
    echo "    $0 --level 3"
    echo ""
    echo "NOTES:"
    echo "    • .env is always backed up to _trash/ before removal"
    echo "    • Level 1 deletes databases but keeps files/, config/, data/"
    echo "    • Level 2 deletes everything except Docker images"
    echo "    • Level 3 deletes absolutely everything"
    echo "    • Use ./setup.sh to reinstall after cleanup"
    echo ""
}

# Parse arguments
CLEANUP_LEVEL=""
NON_INTERACTIVE=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--level)
                CLEANUP_LEVEL="$2"
                if [[ ! "$CLEANUP_LEVEL" =~ ^[1-3]$ ]]; then
                    log_error "Invalid level: $CLEANUP_LEVEL (must be 1, 2, or 3)"
                    exit 1
                fi
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
    done
}

show_cleanup_level_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                                    ║${NC}"
    echo -e "${CYAN}║${NC}          ${BOLD}WeekendStack Cleanup - Choose Level${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Select cleanup level:${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} ${BOLD}Quick Reset${NC} (soft reset - keeps images and user data)"
    echo "   • Stop and remove all containers"
    echo "   • Remove .env, docker-compose.custom.yml, SETUP_SUMMARY.md"
    echo "   • Remove all Docker volumes (deletes databases)"
    echo "   • Remove all Docker networks"
    echo -e "   ${GREEN}✓ Keep:${NC} Images, data/, files/, config/"
    echo ""
    echo -e "${YELLOW}2)${NC} ${BOLD}Full Reset${NC} (re-staging - removes all data)"
    echo "   • Everything from Level 1"
    echo "   • Remove data/ directory (application state)"
    echo "   • Remove files/ directory (your documents/photos)"
    echo "   • Remove config/ directory (certificates/settings)"
    echo -e "   ${GREEN}✓ Keep:${NC} Images (no re-download needed)"
    echo ""
    echo -e "${RED}3)${NC} ${BOLD}Complete Cleanup${NC} (nuclear - removes everything)"
    echo "   • Everything from Level 2"
    echo "   • Remove all Docker images (~2-10GB)"
    echo -e "   ${RED}✗ Nothing is kept${NC}"
    echo ""
    echo -ne "Enter level [1-3] or 'q' to quit: "
}

prompt_for_level() {
    if [[ -n "$CLEANUP_LEVEL" ]]; then
        return 0
    fi
    
    while true; do
        show_cleanup_level_menu
        read -r choice
        
        case "$choice" in
            1|2|3)
                CLEANUP_LEVEL="$choice"
                return 0
                ;;
            q|Q)
                echo ""
                log_info "Cleanup cancelled"
                exit 0
                ;;
            *)
                echo ""
                log_error "Invalid choice. Please enter 1, 2, 3, or 'q'"
                sleep 2
                ;;
        esac
    done
}

show_confirmation() {
    local level="$1"
    
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                                    ║${NC}"
    echo -e "${CYAN}║${NC}                  ${BOLD}Cleanup Confirmation${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    case "$level" in
        1)
            echo -e "${BOLD}Level 1 - Quick Reset${NC} (soft reset)"
            echo ""
            echo -e "${YELLOW}${BOLD}⚠️  WARNING: This will DELETE all databases! ⚠️${NC}"
            echo ""
            echo "This will:"
            echo -e "  ${RED}✗${NC} Stop and remove all containers"
            echo -e "  ${RED}✗${NC} Remove .env file (backed up to _trash/)"
            echo -e "  ${RED}✗${NC} Remove docker-compose.custom.yml"
            echo -e "  ${RED}✗${NC} Remove SETUP_SUMMARY.md"
            echo -e "  ${RED}✗${NC} Remove ALL Docker volumes (databases DELETED)"
            echo -e "  ${RED}✗${NC} Remove ALL Docker networks"
            echo ""
            echo "This will keep:"
            echo -e "  ${GREEN}✓${NC} Docker images (no re-download needed)"
            echo -e "  ${GREEN}✓${NC} Application data (data/)"
            echo -e "  ${GREEN}✓${NC} User files (files/)"
            echo -e "  ${GREEN}✓${NC} Configuration (config/)"
            ;;
        2)
            echo -e "${BOLD}${YELLOW}Level 2 - Full Reset${NC} (re-staging)"
            echo ""
            echo -e "${RED}${BOLD}⚠️  WARNING: This will DELETE databases, files, and config! ⚠️${NC}"
            echo ""
            echo "This will:"
            echo -e "  ${RED}✗${NC} Everything from Level 1"
            echo -e "  ${RED}✗${NC} Remove data/ directory (application state)"
            echo -e "  ${RED}✗${NC} Remove files/ directory (YOUR documents/photos/media)"
            echo -e "  ${RED}✗${NC} Remove config/ directory (certificates/settings)"
            echo ""
            echo "This will keep:"
            echo -e "  ${GREEN}✓${NC} Docker images (no re-download needed)"
            echo ""
            echo -e "${YELLOW}Note:${NC} Images are kept - quick re-setup possible"
            ;;
        3)
            echo -e "${BOLD}${RED}Level 3 - Complete Cleanup${NC} (nuclear)"
            echo ""
            echo -e "${RED}${BOLD}⚠️  WARNING: This deletes EVERYTHING. Nothing is kept! ⚠️${NC}"
            echo ""
            echo "This will:"
            echo -e "  ${RED}✗${NC} Everything from Level 2"
            echo -e "  ${RED}✗${NC} Remove ALL Docker images (~2-10GB)"
            echo ""
            echo -e "${RED}Nothing is preserved. Full re-download required on next setup.${NC}"
            ;;
    esac
    
    echo ""
    
    if $NON_INTERACTIVE; then
        log_info "Non-interactive mode: proceeding with level $level"
        return 0
    fi
    
    echo ""
    log_warn "Type 'UNINSTALL' to confirm and proceed with Level $level cleanup:"
    read -r confirmation
    
    if [[ "$confirmation" != "UNINSTALL" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    return 0
}

backup_env() {
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        local timestamp=$(date +%Y%m%d-%H%M%S)
        local backup_dir="$SCRIPT_DIR/_trash"
        mkdir -p "$backup_dir"
        
        cp "$SCRIPT_DIR/.env" "$backup_dir/.env.backup.$timestamp"
        log_success "Backed up .env to: _trash/.env.backup.$timestamp"
    else
        log_info "No .env file to backup"
    fi
}

stop_and_remove_containers() {
    log_header "Stopping and Removing Containers"
    
    cd "$SCRIPT_DIR"
    
    # Get all container IDs
    local containers=$(docker ps -aq 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        log_info "Removing $(echo "$containers" | wc -l) containers..."
        echo "$containers" | xargs docker rm -f >/dev/null 2>&1 || true
        log_success "All containers removed"
    else
        log_info "No containers to remove"
    fi
}

remove_setup_files() {
    log_header "Removing Setup Files"
    
    local files_removed=0
    
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        rm -f "$SCRIPT_DIR/.env"
        log_success "Removed .env"
        files_removed=$((files_removed + 1))
    fi
    
    if [[ -f "$SCRIPT_DIR/docker-compose.custom.yml" ]]; then
        rm -f "$SCRIPT_DIR/docker-compose.custom.yml"
        log_success "Removed docker-compose.custom.yml"
        files_removed=$((files_removed + 1))
    fi
    
    if [[ -f "$SCRIPT_DIR/SETUP_SUMMARY.md" ]]; then
        rm -f "$SCRIPT_DIR/SETUP_SUMMARY.md"
        log_success "Removed SETUP_SUMMARY.md"
        files_removed=$((files_removed + 1))
    fi
    
    if [[ -f "$SCRIPT_DIR/CLEANUP_SUMMARY.md" ]]; then
        rm -f "$SCRIPT_DIR/CLEANUP_SUMMARY.md"
        log_success "Removed previous CLEANUP_SUMMARY.md"
        files_removed=$((files_removed + 1))
    fi

    # Remove Coder template deployment marker so fresh installs always re-deploy
    local coder_marker="$SCRIPT_DIR/config/coder/.template_deployment_complete"
    if [[ -f "$coder_marker" ]]; then
        rm -f "$coder_marker"
        log_success "Removed Coder template deployment marker"
        files_removed=$((files_removed + 1))
    fi
    
    if [[ $files_removed -eq 0 ]]; then
        log_info "No setup files to remove"
    fi
}

remove_images() {
    log_header "Removing Docker Images"
    
    # Get all images
    local images=$(docker images -q 2>/dev/null || true)
    
    if [[ -n "$images" ]]; then
        local image_count=$(echo "$images" | wc -l)
        log_info "Removing $image_count Docker images..."
        
        # Get disk space before
        local space_before=$(docker system df --format "{{.Size}}" 2>/dev/null | head -n1 || echo "unknown")
        
        echo "$images" | xargs docker rmi -f >/dev/null 2>&1 || true
        
        # Clean up dangling images
        docker image prune -af >/dev/null 2>&1 || true
        
        log_success "All images removed"
        log_info "Freed disk space: $space_before"
    else
        log_info "No images to remove"
    fi
}

remove_volumes() {
    log_header "Removing Docker Volumes"
    
    log_warn "This will DELETE all databases and application data!"
    
    # Get all volumes
    local volumes=$(docker volume ls -q 2>/dev/null || true)
    
    if [[ -n "$volumes" ]]; then
        local volume_count=$(echo "$volumes" | wc -l)
        log_info "Removing $volume_count Docker volumes..."
        
        echo "$volumes" | xargs docker volume rm -f >/dev/null 2>&1 || true
        
        log_success "All volumes removed"
    else
        log_info "No volumes to remove"
    fi
}

remove_networks() {
    log_header "Removing Docker Networks"
    
    local networks=(
        "shared-network"
        "traefik-network"
        "coder-network"
        "core-network"
        "productivity-network"
        "media-network"
        "ai-network"
        "automation-network"
        "monitoring-network"
        "weekendstack_default"
    )
    local removed=0
    
    for network in "${networks[@]}"; do
        if docker network inspect "$network" >/dev/null 2>&1; then
            if docker network rm "$network" >/dev/null 2>&1; then
                log_success "Removed network: $network"
                removed=$((removed + 1))
            else
                log_warn "Could not remove network: $network (may be in use)"
            fi
        fi
    done
    
    if [[ $removed -eq 0 ]]; then
        log_info "No networks to remove"
    fi
}

remove_data_directory() {
    log_header "Removing Data Directory"
    
    local data_dir="$SCRIPT_DIR/data"
    
    if [[ ! -d "$data_dir" ]]; then
        log_info "Data directory does not exist"
        return 0
    fi
    
    local size=$(du -sh "$data_dir" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Data directory size: $size"
    
    rm -rf "$data_dir" 2>/dev/null || sudo rm -rf "$data_dir"
    log_success "Data directory removed"

    _cleanup_phantom_dirs
}

# Remove Docker-created phantom directories at paths that must be files.
# These block the next docker compose up if left behind as directories.
_cleanup_phantom_dirs() {
    local phantom_paths=(
        "$SCRIPT_DIR/config/traefik/config.yml"
        "$SCRIPT_DIR/config/glance/glance.yml"
        "$SCRIPT_DIR/config/filebrowser/init-filebrowser.sh"
    )
    for path in "${phantom_paths[@]}"; do
        if [[ -d "$path" ]]; then
            rmdir "$path" 2>/dev/null || rm -rf "$path"
            log_info "Removed phantom directory: $path"
        fi
    done
}

remove_files_and_config() {
    log_header "Removing User Files and Generated Configuration"

    # Wipe user media files (not git-tracked)
    local files_dir="$SCRIPT_DIR/files"
    if [[ -d "$files_dir" ]]; then
        local size=$(du -sh "$files_dir" 2>/dev/null | cut -f1 || echo "unknown")
        log_info "Removing files/ ($size)..."
        rm -rf "$files_dir" 2>/dev/null || sudo rm -rf "$files_dir"
        log_success "Removed files/"
    fi

    # config/: delete only generated/runtime artifacts — never touch static tracked files.
    # This list mirrors exactly what setup.sh / directory-creator.sh creates.
    # Static files (traefik auth YAMLs, middleware configs, v2 templates, .example
    # files, etc.) are intentionally absent from this list; they need no cleanup.
    log_info "Removing generated config artifacts..."

    local removed_count=0
    _rm_generated() {
        local target="$1"
        if [[ -e "$target" || -L "$target" ]]; then
            rm -rf "$target" 2>/dev/null || sudo rm -rf "$target"
            log_info "  Removed: ${target#$SCRIPT_DIR/}"
            removed_count=$((removed_count + 1))
        fi
    }

    # Coder deploy scripts — copied from tools/coder/scripts/ by setup.
    # push-template.sh is tracked and must NOT be deleted.
    _rm_generated "$SCRIPT_DIR/config/coder/scripts/deploy-all-templates.sh"
    _rm_generated "$SCRIPT_DIR/config/coder/scripts/lib"

    # Coder runtime state files — generated during template push / setup
    _rm_generated "$SCRIPT_DIR/config/coder/.versions.json"
    _rm_generated "$SCRIPT_DIR/config/coder/.template_deployment_complete"

    # Traefik static config — copied from config.yml.example by setup
    _rm_generated "$SCRIPT_DIR/config/traefik/config.yml"

    # Traefik TLS certificates — generated by certificate helper
    find "$SCRIPT_DIR/config/traefik/certs" -type f \
        \( -name "*.crt" -o -name "*.key" -o -name "*.pem" -o -name "*.p12" \) \
        -delete 2>/dev/null || true

    # Traefik auth secrets — htpasswd and other generated auth files
    find "$SCRIPT_DIR/config/traefik/auth" -type f -name "*.htpasswd" \
        -delete 2>/dev/null || true

    # Glance dashboard — copied from glance.yml.example by setup
    _rm_generated "$SCRIPT_DIR/config/glance/glance.yml"

    # Cloudflare tunnel config and credentials
    _rm_generated "$SCRIPT_DIR/config/cloudflare/config.yml"
    _rm_generated "$SCRIPT_DIR/config/cloudflare/.cloudflared"

    # Pi-hole runtime state (DBs, tokens, hashes)
    _rm_generated "$SCRIPT_DIR/config/pihole/etc-pihole"

    # Filebrowser — empty placeholder pre-created to prevent Docker phantom dir
    _rm_generated "$SCRIPT_DIR/config/filebrowser/init-filebrowser.sh"

    if [[ $removed_count -eq 0 ]]; then
        log_info "No generated config artifacts to remove"
    else
        log_success "Removed $removed_count generated config artifact(s)"
    fi
}

generate_cleanup_summary() {
    local level="$1"
    local summary_file="$SCRIPT_DIR/CLEANUP_SUMMARY.md"
    
    cat > "$summary_file" << EOF
# WeekendStack Cleanup Summary

**Cleanup completed:** $(date +"%Y-%m-%d %H:%M:%S")
**Cleanup level:** $level

## What Was Removed

EOF
    
    echo "- ✓ All Docker containers" >> "$summary_file"
    echo "- ✓ .env file (backed up to _trash/)" >> "$summary_file"
    echo "- ✓ docker-compose.custom.yml" >> "$summary_file"
    echo "- ✓ SETUP_SUMMARY.md" >> "$summary_file"
    echo "- ✓ All Docker volumes (databases deleted)" >> "$summary_file"
    echo "- ✓ All Docker networks" >> "$summary_file"
    
    if [[ "$level" -ge 2 ]]; then
        echo "- ✓ data/ directory (application state deleted)" >> "$summary_file"
        echo "- ✓ files/ directory (user documents/photos deleted)" >> "$summary_file"
        echo "- ✓ config/ directory (certificates/settings deleted)" >> "$summary_file"
    fi
    
    if [[ "$level" -ge 3 ]]; then
        echo "- ✓ All Docker images" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF

## What Was Kept

EOF
    
    if [[ "$level" -lt 2 ]]; then
        echo "- ✓ Application data (data/)" >> "$summary_file"
        echo "- ✓ files/ directory (your documents/photos)" >> "$summary_file"
        echo "- ✓ config/ directory (certificates/settings)" >> "$summary_file"
    fi
    
    if [[ "$level" -lt 3 ]]; then
        echo "- ✓ Docker images (no re-download needed)" >> "$summary_file"
    fi
    
    echo "- ✓ Docker Compose files" >> "$summary_file"
    echo "- ✓ Documentation (docs/)" >> "$summary_file"
    echo "- ✓ Scripts (tools/)" >> "$summary_file"
    
    cat >> "$summary_file" << EOF

## Backups

.env backup location: \`_trash/\`

Latest backup: \`$(ls -t "$SCRIPT_DIR/_trash"/.env.backup.* 2>/dev/null | head -n1 | xargs basename 2>/dev/null || echo "none")\`

## Reinstallation

To reinstall WeekendStack:

\`\`\`bash
./setup.sh
\`\`\`

EOF
    
    if [[ "$level" -ge 2 ]]; then
        cat >> "$summary_file" << EOF
**Note:** All databases and application state were deleted.
Your setup will be completely fresh.

EOF
    fi
    
    if [[ "$level" -ge 3 ]]; then
        cat >> "$summary_file" << EOF
**Note:** Docker images will be re-downloaded during setup.

EOF
    fi
    
    cat >> "$summary_file" << EOF
## System Status

Run these commands to verify cleanup:

\`\`\`bash
# Check containers (should be empty)
docker ps -a

# Check images
docker images

# Check volumes
docker volume ls

# Check networks
docker network ls
\`\`\`

---
*Generated by WeekendStack Uninstall Script v$VERSION*
EOF
    
    log_success "Cleanup summary saved to: CLEANUP_SUMMARY.md"
}

execute_cleanup() {
    local level="$1"
    
    echo ""
    log_header "Starting Cleanup (Level $level)"
    echo ""
    
    # Always backup .env if it exists
    backup_env
    
    # Level 1+: containers, setup files, volumes, networks
    stop_and_remove_containers
    remove_setup_files
    remove_volumes
    remove_networks
    
    # Level 2+: data directory, user files, config
    if [[ "$level" -ge 2 ]]; then
        remove_data_directory
        remove_files_and_config
    fi
    
    # Level 3: images
    if [[ "$level" -ge 3 ]]; then
        remove_images
    fi
    
    # Generate summary
    generate_cleanup_summary "$level"
    
    echo ""
    log_success "Cleanup complete!"
    echo ""
    echo "Summary: cat CLEANUP_SUMMARY.md"
    echo "Reinstall: ./setup.sh"
    echo ""
}
main() {
    parse_args "$@"
    
    cd "$SCRIPT_DIR"
    
    # Prompt for cleanup level if not specified
    prompt_for_level
    
    # Show confirmation and get approval
    show_confirmation "$CLEANUP_LEVEL"
    
    # Execute the cleanup
    execute_cleanup "$CLEANUP_LEVEL"
}

main "$@"
