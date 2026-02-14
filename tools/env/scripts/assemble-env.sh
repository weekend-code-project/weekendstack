#!/usr/bin/env bash
# ============================================================================
# assemble-env.sh - Assemble modular env templates into single .env file
# ============================================================================
# This script combines service-specific environment template files based on
# selected profiles to create a consolidated .env.example file.
#
# Usage:
#   ./tools/env/scripts/assemble-env.sh --profiles "core,ai" [--output .env.assembled] [--preview]
#
# Options:
#   --profiles   Comma-separated list of profiles (required)
#   --output     Output file path (default: .env.assembled)
#   --preview    Display output to stdout instead of writing file
#   --help       Show this help message
#
# Examples:
#   # Assemble core and AI profiles
#   ./tools/env/scripts/assemble-env.sh --profiles "core,ai"
#
#   # Preview what would be generated
#   ./tools/env/scripts/assemble-env.sh --profiles "core,ai,productivity" --preview
#
# ============================================================================

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TEMPLATES_DIR="${REPO_ROOT}/tools/env/templates"
MAPPINGS_DIR="${REPO_ROOT}/tools/env/mappings"
DEFAULT_OUTPUT="${REPO_ROOT}/.env.assembled"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
PROFILES=""
OUTPUT_FILE="$DEFAULT_OUTPUT"
PREVIEW_MODE=false

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_section() {
    echo -e "${CYAN}[SECTION]${NC} $1" >&2
}

# Show usage help
show_usage() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //g' | sed 's/^#//g'
    exit 0
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profiles)
                PROFILES="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --preview)
                PREVIEW_MODE=true
                shift
                ;;
            --help|-h)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done
    
    if [[ -z "$PROFILES" ]]; then
        log_error "Missing required --profiles argument"
        show_usage
    fi
}

# Validate prerequisites
validate_prerequisites() {
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log_error "Templates directory not found: $TEMPLATES_DIR"
        log_info "Run migration script first: ./tools/env/scripts/migrate-monolith.sh"
        exit 1
    fi
    
    if [[ ! -f "${MAPPINGS_DIR}/profile-to-services.json" ]]; then
        log_error "Profile mapping not found: ${MAPPINGS_DIR}/profile-to-services.json"
        exit 1
    fi
    
    if [[ ! -f "${MAPPINGS_DIR}/service-metadata.json" ]]; then
        log_error "Service metadata not found: ${MAPPINGS_DIR}/service-metadata.json"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Install with: sudo apt install jq"
        exit 1
    fi
}

# Get list of services for selected profiles
get_services_for_profiles() {
    local profiles_array=(${PROFILES//,/ })
    local all_services=()
    
    # Check if 'all' profile is selected
    for profile in "${profiles_array[@]}"; do
        if [[ "$profile" == "all" ]]; then
            # Return all services from all profiles
            jq -r '.[] | .[]' "${MAPPINGS_DIR}/profile-to-services.json" | sort -u
            return 0
        fi
    done
    
    # Collect services for each selected profile
    for profile in "${profiles_array[@]}"; do
        local services=$(jq -r --arg profile "$profile" '.[$profile] // [] | .[]' "${MAPPINGS_DIR}/profile-to-services.json")
        if [[ -n "$services" ]]; then
            all_services+=($services)
        else
            log_warn "Profile not found or empty: $profile"
        fi
    done
    
    # Remove duplicates and sort
    printf '%s\n' "${all_services[@]}" | sort -u
}

# Generate file header
generate_header() {
    local profiles_list="$1"
    local services_count="$2"
    local setup_date=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    cat <<EOF
# ============================================================================
# WEEKENDSTACK - ENVIRONMENT CONFIGURATION
# ============================================================================
# This file was auto-assembled from modular templates
#
# Assembly Date:     $setup_date
# Selected Profiles: $profiles_list
# Services Included: $services_count services
#
# SETUP INSTRUCTIONS:
# 1. Review and customize all values marked with <CUSTOMIZE>
# 2. Generate secure passwords and secrets (see commands below)
# 3. Run validation: ./tools/validate-env.sh
#
# Password Generation Commands:
#   Standard Password (32 chars): openssl rand -hex 32
#   JWT Secret (64 chars):        openssl rand -hex 64  
#   Encryption Key (32 chars):    openssl rand -hex 32
#   App Key (base64, 32 chars):   openssl rand -base64 32
#
# Quick Setup (auto-generate all secrets):
#   ./tools/env-template-gen.sh
#
# ============================================================================

# ============================================================================
# SETUP METADATA
# ============================================================================
# These values are set automatically by setup.sh
# DO NOT manually edit unless you know what you're doing
# ============================================================================
SETUP_COMPLETED=false
SETUP_DATE=
SELECTED_PROFILES=$profiles_list

# Default Profile Selection
# Using 'custom' profile which includes all services from: $profiles_list
# See docker-compose.custom.yml for generated profile mappings
COMPOSE_PROFILES=custom

EOF
}

# Assemble env file
assemble_env() {
    local services=($(get_services_for_profiles))
    local services_count=${#services[@]}
    
    if [[ $services_count -eq 0 ]]; then
        log_error "No services found for profiles: $PROFILES"
        exit 1
    fi
    
    log_info "Assembling environment for profiles: $PROFILES"
    log_info "Services to include: $services_count"
    
    # Create temporary file for assembly
    local temp_file=$(mktemp)
    
    # Generate header
    log_section "Generating header..."
    generate_header "$PROFILES" "$services_count" > "$temp_file"
    
    # Add global templates
    log_section "Adding global variables..."
    for global_template in "${TEMPLATES_DIR}/global"/*.env.example; do
        if [[ -f "$global_template" ]]; then
            echo "" >> "$temp_file"
            cat "$global_template" >> "$temp_file"
        fi
    done
    
    # Add service templates
    log_section "Adding service templates..."
    for service in "${services[@]}"; do
        local template_path=$(jq -r --arg svc "$service" '.[$svc].template // empty' "${MAPPINGS_DIR}/service-metadata.json")
        
        if [[ -z "$template_path" ]]; then
            log_warn "No template found for service: $service"
            continue
        fi
        
        local full_path="${TEMPLATES_DIR}/${template_path}"
        
        if [[ -f "$full_path" ]]; then
            echo "" >> "$temp_file"
            echo "# ============================================================================" >> "$temp_file"
            cat "$full_path" >> "$temp_file"
            log_info "  ✓ Added: $service"
        else
            log_warn "Template file not found: $full_path"
        fi
    done
    
    # Add footer
    {
        echo ""
        echo "# ============================================================================"
        echo "# END OF CONFIGURATION"
        echo "# ============================================================================"
    } >> "$temp_file"
    
    # Output result
    if [[ "$PREVIEW_MODE" == true ]]; then
        cat "$temp_file"
        rm -f "$temp_file"
    else
        mv "$temp_file" "$OUTPUT_FILE"
        log_success "Assembled environment written to: $OUTPUT_FILE"
        log_info "File size: $(wc -l < "$OUTPUT_FILE") lines (original: 804 lines)"
        log_info "Variables reduced: ~$(grep -c "^[A-Z_]*=" "$OUTPUT_FILE" 2>/dev/null || echo 0) variables"
    fi
}

# Generate service list summary
generate_summary() {
    local services=($(get_services_for_profiles))
    
    echo ""
    echo "Services included in this configuration:"
    echo "=========================================="
    
    for service in "${services[@]}"; do
        local display_name=$(jq -r --arg svc "$service" '.[$svc].display_name // $svc' "${MAPPINGS_DIR}/service-metadata.json")
        local description=$(jq -r --arg svc "$service" '.[$svc].description // ""' "${MAPPINGS_DIR}/service-metadata.json")
        printf "  %-25s %s\n" "$display_name" "$description"
    done
    
    echo ""
}

# Main execution
main() {
    parse_arguments "$@"
    
    if [[ "$PREVIEW_MODE" == false ]]; then
        echo ""
        echo "============================================================================"
        echo " WeekendStack - Environment Assembly"
        echo "============================================================================"
        echo ""
    fi
    
    validate_prerequisites
    assemble_env
    
    if [[ "$PREVIEW_MODE" == false ]]; then
        generate_summary
        echo "Next steps:"
        echo "  1. Review assembled file: $OUTPUT_FILE"
        echo "  2. Generate secrets: ./tools/env-template-gen.sh"
        echo "  3. Copy to .env: cp $OUTPUT_FILE .env"
        echo ""
    fi
}

main "$@"
