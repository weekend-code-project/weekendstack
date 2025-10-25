#!/bin/bash
# =============================================================================
# CODER TEMPLATES BACKUP SCRIPT
# =============================================================================
# This script backs up all Coder templates from a running Coder instance
# to the local templates directory for safekeeping and version control.
#
# Usage:
#   ./backup-templates.sh [CODER_URL] [OUTPUT_DIR]
#
# Examples:
#   ./backup-templates.sh                                    # Use defaults
#   ./backup-templates.sh http://localhost:7080 ./templates  # Custom settings
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
CODER_URL="${1:-http://localhost:7080}"
OUTPUT_DIR="${2:-$(dirname "$0")/../templates}"
BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DIR="/tmp/coder_backup_$$"
EXCLUDE_MODULES="${3:-true}"  # Set to "false" to include modules folder

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Function to check if Coder is accessible
check_coder_access() {
    log "Checking Coder accessibility at $CODER_URL..."
    
    if curl -s --connect-timeout 5 "$CODER_URL/healthz" > /dev/null 2>&1; then
        log "✅ Coder is accessible"
        return 0
    else
        log_error "❌ Cannot connect to Coder at $CODER_URL"
        log_error "Please ensure:"
        log_error "  1. Coder is running"
        log_error "  2. URL is correct: $CODER_URL"
        log_error "  3. No authentication issues"
        return 1
    fi
}

# Function to backup templates using Coder CLI (if available)
backup_with_cli() {
    log "Attempting backup using Coder CLI..."
    
    # Check for coder CLI (local or copied from Docker)
    local CODER_CMD=""
    if command -v coder &> /dev/null; then
        CODER_CMD="coder"
    elif [ -f "/tmp/coder-cli" ]; then
        CODER_CMD="/tmp/coder-cli"
    else
        log_warn "Coder CLI not found, skipping CLI method"
        return 1
    fi
    
    # Set Coder URL
    export CODER_URL="$CODER_URL"
    
    # List templates
    log "Fetching template list..."
    if ! $CODER_CMD templates list &> /dev/null; then
        log_warn "Failed to list templates with CLI (might need authentication)"
        return 1
    fi
    
    # Get template names
    local templates
    templates=$($CODER_CMD templates list --output json 2>/dev/null | jq -r '.[].Template.name' 2>/dev/null || echo "")
    
    if [[ -z "$templates" ]]; then
        log_warn "No templates found or failed to parse template list"
        return 1
    fi
    
    # Backup each template
    mkdir -p "$OUTPUT_DIR"
    for template in $templates; do
        log "📥 Pulling template: $template"
        local template_dir="$OUTPUT_DIR/${template}"
        
        # Remove existing directory if it exists
        if [[ -d "$template_dir" ]]; then
            log "  Removing existing directory..."
            rm -rf "$template_dir"
        fi
        
        # Pull template to directory
        if $CODER_CMD templates pull "$template" "$template_dir" 2>/dev/null; then
            # Remove bundled module files (since we maintain them separately in modules/)
            if [[ "$EXCLUDE_MODULES" == "true" ]]; then
                log "  🗑️  Removing bundled module files (maintained separately)"
                # Remove individual module .tf files that match our known modules
                for module_file in "$MODULES_DIR"/*.tf 2>/dev/null; do
                    if [[ -f "$module_file" ]]; then
                        local basename_module=$(basename "$module_file")
                        if [[ -f "$template_dir/$basename_module" ]]; then
                            rm -f "$template_dir/$basename_module"
                            log "    Removed $basename_module"
                        fi
                    fi
                done
            fi
            
            log "  ✅ Backed up $template"
        else
            log_error "  ❌ Failed to backup $template"
        fi
    done
    
    return 0
}

# Function to backup templates using API calls
backup_with_api() {
    log "Attempting backup using Coder API..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Try to get templates list via API
    log "Fetching templates via API..."
    
    # First, try to get the templates list
    local templates_json
    if ! templates_json=$(curl -s "$CODER_URL/api/v2/templates" 2>/dev/null); then
        log_error "Failed to fetch templates from API"
        return 1
    fi
    
    # Check if we got valid JSON and extract template info
    if ! echo "$templates_json" | jq . > /dev/null 2>&1; then
        log_error "Invalid JSON response from templates API"
        return 1
    fi
    
    # Extract template names and IDs
    local template_data
    template_data=$(echo "$templates_json" | jq -r '.[] | "\(.name)|\(.id)"' 2>/dev/null || echo "")
    
    if [[ -z "$template_data" ]]; then
        log_warn "No templates found in API response"
        return 1
    fi
    
    # Backup each template
    mkdir -p "$OUTPUT_DIR"
    while IFS='|' read -r name id; do
        [[ -z "$name" ]] && continue
        
        log "Backing up template: $name (ID: $id)"
        
        # Try to download template archive
        local output_file="$OUTPUT_DIR/${name}_${BACKUP_TIMESTAMP}.tar.gz"
        
        if curl -s "$CODER_URL/api/v2/templates/$id/archive" -o "$output_file" 2>/dev/null; then
            # Check if we got a valid archive
            if file "$output_file" | grep -q "gzip\|tar"; then
                log "✅ Backed up $name to $output_file"
            else
                log_warn "Downloaded file for $name doesn't appear to be an archive, keeping anyway"
            fi
        else
            log_error "❌ Failed to download archive for $name"
        fi
        
    done <<< "$template_data"
    
    return 0
}

# Function to create a manifest of backed up templates
create_manifest() {
    # Skip manifest to avoid cluttering directories
    return 0
}

# Main execution
main() {
    log "🚀 Starting Coder templates backup..."
    log "Source: $CODER_URL"
    log "Destination: $OUTPUT_DIR"
    
    if [[ "$EXCLUDE_MODULES" == "true" ]]; then
        log "Mode: Exclude bundled modules (maintained separately)"
    else
        log "Mode: Include bundled modules"
    fi
    
    # Check if Coder is accessible
    if ! check_coder_access; then
        exit 1
    fi
    
    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR"
    
    # Try CLI method first, then API method
    if backup_with_cli; then
        log "✅ Backup completed using Coder CLI"
    elif backup_with_api; then
        log "✅ Backup completed using Coder API"
    else
        log_error "❌ All backup methods failed"
        log_error "Manual backup required:"
        log_error "  1. Access Coder UI at $CODER_URL"
        log_error "  2. Navigate to Templates"
        log_error "  3. Download each template manually"
        exit 1
    fi
    
    # Create manifest
    create_manifest
    
    # Cleanup
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    
    log "🎉 Backup process completed!"
    log "Templates saved to: $OUTPUT_DIR"
    
    # Show what was backed up
    echo ""
    echo -e "${BLUE}📁 Backed up templates:${NC}"
    find "$OUTPUT_DIR" -maxdepth 1 -type d ! -name "$(basename "$OUTPUT_DIR")" ! -name "_*" ! -name ".*" | sort | while read -r dir; do
        echo "  $(basename "$dir")"
    done
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Coder Templates Backup Script"
    echo ""
    echo "Usage: $0 [CODER_URL] [OUTPUT_DIR] [EXCLUDE_MODULES]"
    echo ""
    echo "Arguments:"
    echo "  CODER_URL         URL of Coder instance (default: http://localhost:7080)"
    echo "  OUTPUT_DIR        Directory to save templates (default: ../templates)"
    echo "  EXCLUDE_MODULES   Exclude bundled modules folder - 'true' or 'false' (default: true)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Backup from localhost, exclude modules"
    echo "  $0 http://coder.example.com  # Backup from remote, exclude modules"
    echo "  $0 \"\" \"\" false             # Backup with modules included"
    echo ""
    echo "Notes:"
    echo "  - Templates are saved as directories (not tar files)"
    echo "  - By default, bundled modules/ folders are excluded (maintained separately)"
    echo "  - Set EXCLUDE_MODULES=false to keep bundled modules in backed up templates"
    echo ""
    exit 0
fi

# Run main function
main "$@"
