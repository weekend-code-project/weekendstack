#!/bin/bash
# Extract metadata from Coder templates
# Returns JSON with template name, description, module count, and deployment status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TEMPLATES_DIR="$WORKSPACE_ROOT/config/coder/templates"

# Get template info for a single template
get_template_info() {
    local template_name="$1"
    local template_dir="$TEMPLATES_DIR/$template_name"
    
    if [[ ! -d "$template_dir" ]]; then
        echo "{\"error\": \"Template not found: $template_name\"}"
        return 1
    fi
    
    # Extract description from README.md if it exists
    local description="Coder workspace template"
    if [[ -f "$template_dir/README.md" ]]; then
        # Get first line after # heading
        description=$(grep -m 1 "^#" "$template_dir/README.md" 2>/dev/null | sed 's/^#\+\s*//' || echo "Coder workspace template")
    fi
    
    # Count modules (look for module blocks in .tf files)
    local module_count=0
    if [[ -d "$template_dir" ]]; then
        module_count=$(grep -r "^module " "$template_dir"/*.tf 2>/dev/null | wc -l || echo 0)
    fi
    
    # Check if deployed by querying Coder (if container is running)
    local deployed="false"
    local version="unknown"
    if docker ps --format '{{.Names}}' | grep -q '^coder$'; then
        if docker exec coder coder templates list 2>/dev/null | grep -q "$template_name"; then
            deployed="true"
            # Try to get version
            version=$(docker exec coder coder templates list 2>/dev/null | grep "$template_name" | awk '{print $2}' || echo "unknown")
        fi
    fi
    
    # Output JSON
    cat <<EOF
{
  "name": "$template_name",
  "description": "$description",
  "modules": $module_count,
  "deployed": $deployed,
  "version": "$version"
}
EOF
}

# List all templates with their info
list_all_templates() {
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        echo "{\"error\": \"Templates directory not found: $TEMPLATES_DIR\"}"
        return 1
    fi
    
    local templates=()
    while IFS= read -r template_dir; do
        local template_name=$(basename "$template_dir")
        if [[ -f "$template_dir/main.tf" ]]; then
            templates+=("$template_name")
        fi
    done < <(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
    
    echo "["
    local first=true
    for template in "${templates[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        get_template_info "$template" | sed 's/^/  /'
    done
    echo ""
    echo "]"
}

# Display template info in human-readable format
display_template_info() {
    local template_name="$1"
    local info=$(get_template_info "$template_name")
    
    local description=$(echo "$info" | grep -o '"description": "[^"]*"' | cut -d'"' -f4)
    local modules=$(echo "$info" | grep -o '"modules": [0-9]*' | awk '{print $2}')
    local deployed=$(echo "$info" | grep -o '"deployed": [a-z]*' | awk '{print $2}')
    local version=$(echo "$info" | grep -o '"version": "[^"]*"' | cut -d'"' -f4)
    
    local status_icon="○"
    [[ "$deployed" == "true" ]] && status_icon="●"
    
    printf "  %s %-20s (%2d modules) - %s" "$status_icon" "$template_name" "$modules" "$description"
    if [[ "$deployed" == "true" && "$version" != "unknown" ]]; then
        printf " [%s]" "$version"
    fi
    printf "\n"
}

# Display all templates
display_all_templates() {
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        echo "Error: Templates directory not found: $TEMPLATES_DIR"
        return 1
    fi
    
    local templates=()
    while IFS= read -r template_dir; do
        local template_name=$(basename "$template_dir")
        if [[ -f "$template_dir/main.tf" ]]; then
            templates+=("$template_name")
        fi
    done < <(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
    
    if [[ ${#templates[@]} -eq 0 ]]; then
        echo "No templates found in $TEMPLATES_DIR"
        return 0
    fi
    
    echo "┌─ Coder Templates ──────────────────────────────────────┐"
    for template in "${templates[@]}"; do
        display_template_info "$template"
    done
    echo "│                                                         │"
    echo "│ Total: ${#templates[@]} templates                                  │"
    echo "└─────────────────────────────────────────────────────────┘"
}

# Main
main() {
    local command="${1:-list}"
    
    case "$command" in
        info)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 info <template-name>"
                exit 1
            fi
            get_template_info "$2"
            ;;
        list)
            list_all_templates
            ;;
        display)
            if [[ -n "${2:-}" ]]; then
                display_template_info "$2"
            else
                display_all_templates
            fi
            ;;
        *)
            echo "Usage: $0 {info|list|display} [template-name]"
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
