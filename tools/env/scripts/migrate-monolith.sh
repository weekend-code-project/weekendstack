#!/usr/bin/env bash
# ============================================================================
# migrate-monolith.sh - Split monolithic .env.example into modular templates
# ============================================================================
# This script parses the existing .env.example file and creates individual
# service template files organized by profile.
#
# Usage:
#   ./tools/env/scripts/migrate-monolith.sh
#
# Output:
#   - Individual service template files in tools/env/templates/{profile}/
#   - Global template files in tools/env/templates/global/
#
# ============================================================================

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ENV_EXAMPLE="${REPO_ROOT}/.env.example"
TEMPLATES_DIR="${REPO_ROOT}/tools/env/templates"
MAPPINGS_DIR="${REPO_ROOT}/tools/env/mappings"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    if [[ ! -f "$ENV_EXAMPLE" ]]; then
        log_error ".env.example not found at: $ENV_EXAMPLE"
        exit 1
    fi
    
    if [[ ! -f "${MAPPINGS_DIR}/service-metadata.json" ]]; then
        log_error "service-metadata.json not found at: ${MAPPINGS_DIR}/service-metadata.json"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Install with: sudo apt install jq"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Extract variables for a specific service
extract_service_variables() {
    local service_name="$1"
    local service_upper=$(echo "$service_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    local output_file="$2"
    local section_start="$3"
    local section_end="$4"
    
    # Create temporary file for this service
    local temp_file=$(mktemp)
    
    # Extract service-specific variables using multiple patterns
    awk -v service="$service_upper" -v start="$section_start" -v end="$section_end" '
        BEGIN { in_section = 0; in_service_block = 0; capture = 0; }
        
        # Track section boundaries
        NR >= start && NR <= end { in_section = 1; }
        NR > end { in_section = 0; }
        
        # Capture service section headers (e.g., "# --- Paperless-NGX ---")
        in_section && /^# ---.*---/ {
            service_header = $0
            gsub(/^# ---[ ]*/, "", service_header)
            gsub(/[ ]*---.*$/, "", service_header)
            gsub(/[ -]/, "_", service_header)
            service_header = toupper(service_header)
            
            if (service_header == service || index(service_header, service) > 0) {
                in_service_block = 1
                print $0
                next
            } else {
                in_service_block = 0
            }
        }
        
        # End service block on next service header or section end
        in_service_block && /^# ---.*---/ && !/^# ---.*'"$service_name"'/ { in_service_block = 0; }
        
        # Capture lines in service block
        in_service_block { print; next; }
        
        # Capture variables with service prefix
        in_section && /^[A-Z_]+=/ {
            var_name = $0
            sub(/=.*$/, "", var_name)
            if (index(var_name, service) == 1) {
                print
            }
        }
        
        # Capture comments before service variables
        in_section && /^#/ && !in_service_block {
            # Store comment
            comment = $0
            getline
            if (/^[A-Z_]+=/) {
                var_name = $0
                sub(/=.*$/, "", var_name)
                if (index(var_name, service) == 1) {
                    print comment
                    print $0
                }
            }
        }
    ' "$ENV_EXAMPLE" > "$temp_file"
    
    # If we found content, write it to the output file
    if [[ -s "$temp_file" ]]; then
        {
            echo "# ============================================================================"
            echo "# $(echo "$service_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_') - Environment Variables"
            echo "# ============================================================================"
            echo ""
            cat "$temp_file"
        } > "$output_file"
        log_success "Created template: $output_file"
    else
        log_warn "No variables found for service: $service_name"
    fi
    
    rm -f "$temp_file"
}

# Extract global variables (system, domains, paths, defaults)
extract_global_variables() {
    log_info "Extracting global variables..."
    
    # Extract SECTION 1: GLOBAL SYSTEM SETTINGS (lines 48-84)
    {
        echo "# ============================================================================"
        echo "# SYSTEM SETTINGS - Environment Variables"
        echo "# ============================================================================"
        echo "# System identification, timezone, network configuration"
        echo "# ============================================================================"
        echo ""
        sed -n '50,84p' "$ENV_EXAMPLE" | grep -v "^# SECTION"
    } > "${TEMPLATES_DIR}/global/system.env.example"
    log_success "Created ${TEMPLATES_DIR}/global/system.env.example"
    
    # Extract SECTION 2: FILE STORAGE PATHS (lines 85-108)
    {
        echo "# ============================================================================"
        echo "# FILE STORAGE PATHS - Environment Variables"
        echo "# ============================================================================"
        echo "# Base directories for data, config, and file storage"
        echo "# ============================================================================"
        echo ""
        sed -n '87,108p' "$ENV_EXAMPLE" | grep -v "^# SECTION"
    } > "${TEMPLATES_DIR}/global/paths.env.example"
    log_success "Created ${TEMPLATES_DIR}/global/paths.env.example"
    
    # Extract SECTION 3: GLOBAL CREDENTIALS (lines 109-167)
    {
        echo "# ============================================================================"
        echo "# GLOBAL CREDENTIALS - Environment Variables"
        echo "# ============================================================================"
        echo "# Default admin credentials and shared secrets"
        echo "# ============================================================================"
        echo ""
        sed -n '111,167p' "$ENV_EXAMPLE" | grep -v "^# SECTION"
    } > "${TEMPLATES_DIR}/global/defaults.env.example"
    log_success "Created ${TEMPLATES_DIR}/global/defaults.env.example"
}

# Extract service variables by profile
extract_service_templates() {
    log_info "Extracting service templates..."
    
    # Read service metadata
    local services=$(jq -r 'keys[]' "${MAPPINGS_DIR}/service-metadata.json")
    
    for service in $services; do
        local template_path=$(jq -r --arg svc "$service" '.[$svc].template' "${MAPPINGS_DIR}/service-metadata.json")
        local full_path="${TEMPLATES_DIR}/${template_path}"
        local profile=$(jq -r --arg svc "$service" '.[$svc].profile' "${MAPPINGS_DIR}/service-metadata.json")
        
        # Determine section boundaries based on profile
        local section_start section_end
        case "$profile" in
            core)
                section_start=168
                section_end=191
                ;;
            ai)
                section_start=192
                section_end=259
                ;;
            productivity)
                section_start=260
                section_end=439
                ;;
            personal)
                section_start=440
                section_end=486
                ;;
            media)
                section_start=487
                section_end=511
                ;;
            automation)
                section_start=512
                section_end=527
                ;;
            dev)
                section_start=528
                section_end=600
                ;;
            monitoring)
                section_start=601
                section_end=672
                ;;
            networking)
                section_start=673
                section_end=712
                ;;
            *)
                log_warn "Unknown profile for service: $service"
                continue
                ;;
        esac
        
        # Extract variables for this service
        extract_service_variables "$service" "$full_path" "$section_start" "$section_end"
    done
}

# Main execution
main() {
    echo ""
    echo "============================================================================"
    echo " WeekendStack - Environment Template Migration"
    echo "============================================================================"
    echo ""
    
    validate_prerequisites
    extract_global_variables
    extract_service_templates
    
    echo ""
    log_success "Migration complete!"
    echo ""
    echo "Summary:"
    echo "  - Global templates: $(find "${TEMPLATES_DIR}/global" -type f | wc -l) files"
    echo "  - Service templates: $(find "${TEMPLATES_DIR}" -type f -not -path "*/global/*" | wc -l) files"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated templates in: ${TEMPLATES_DIR}"
    echo "  2. Test with: ./tools/env/scripts/assemble-env.sh --profiles core --preview"
    echo "  3. Run full setup: ./setup.sh"
    echo ""
}

main "$@"
