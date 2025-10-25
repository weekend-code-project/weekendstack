#!/bin/bash
# =============================================================================
# CODER TEMPLATES PUSH SCRIPT
# =============================================================================
# This script pushes local template files back to a Coder instance.
# Useful for restoring templates after backup or deploying to new instances.
#
# Usage:
#   ./push-templates.sh [CODER_URL] [TEMPLATES_DIR] [VERSION]
#
# Examples:
#   ./push-templates.sh                                    # Use defaults
#   ./push-templates.sh http://localhost:7080 ./templates  # Custom settings
#   ./push-templates.sh http://localhost:7080 ./templates v1  # With version
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
TEMPLATES_DIR="${2:-$(dirname "$0")/../templates}"
VERSION="${3:-auto}"  # Optional version parameter, defaults to "auto" for auto-increment
MODULES_DIR="$(dirname "$0")/../templates/modules"
TEMP_DIR="/tmp/coder_push_$$"
VERSION_FILE="$(dirname "$0")/.template_version"

# Ensure version file exists on fresh checkouts
if [[ ! -f "$VERSION_FILE" ]]; then
    mkdir -p "$(dirname "$VERSION_FILE")"
    echo "{}" > "$VERSION_FILE"
fi

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

# Function to get and increment version
compute_template_hash() {
    local dir="$1"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        echo ""
        return 0
    fi

    # Deterministic hash of all files under dir. Ignore the .terraform dir if present.
    (cd "$dir" && \
        find . -type f ! -path "./.terraform/*" -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}') || echo ""
}

get_next_version() {
    # Usage: get_next_version <template_name> <template_dir>
    local template_name="$1"
    local template_dir="${2:-}"

    # Create version file if it doesn't exist
    if [[ ! -f "$VERSION_FILE" ]]; then
        echo "{}" > "$VERSION_FILE"
    fi

    # Read current record (structured as {version: N, hash: "..."})
    local current_version
    current_version=$(jq -r --arg template "$template_name" '.[$template].version // 0' "$VERSION_FILE" 2>/dev/null || echo "0")
    local current_hash
    current_hash=$(jq -r --arg template "$template_name" '.[$template].hash // ""' "$VERSION_FILE" 2>/dev/null || echo "")

    # Compute current directory hash (if path provided)
    local new_hash=""
    if [[ -n "$template_dir" && -d "$template_dir" ]]; then
        new_hash=$(compute_template_hash "$template_dir" || echo "")
    fi

    # If hash matches and we have a version, reuse it
    if [[ -n "$new_hash" && "$new_hash" == "$current_hash" && "$current_version" != "0" ]]; then
        echo "v${current_version}"
        return 0
    fi

    # Otherwise increment
    local next_version=$((current_version + 1))

    # Update version file with new version and hash
    local temp_file="${VERSION_FILE}.tmp"
    if [[ -n "$new_hash" ]]; then
        jq --arg template "$template_name" --argjson version "$next_version" --arg hash "$new_hash" '.[$template] = {version: $version, hash: $hash}' "$VERSION_FILE" > "$temp_file" && mv "$temp_file" "$VERSION_FILE"
    else
        jq --arg template "$template_name" --argjson version "$next_version" '.[$template] = {version: $version, hash: ""}' "$VERSION_FILE" > "$temp_file" && mv "$temp_file" "$VERSION_FILE"
    fi

    echo "v$next_version"
}

# Function to save version after successful push
save_version() {
    # save_version <template_name> <version> [template_dir]
    local template_name="$1"
    local version="$2"
    local template_dir="${3:-}"

    local numeric_version="${version#v}"

    if [[ ! -f "$VERSION_FILE" ]]; then
        echo "{}" > "$VERSION_FILE"
    fi

    local new_hash=""
    if [[ -n "$template_dir" && -d "$template_dir" ]]; then
        new_hash=$(compute_template_hash "$template_dir" || echo "")
    fi

    local temp_file="${VERSION_FILE}.tmp"
    if [[ -n "$new_hash" ]]; then
        jq --arg template "$template_name" --argjson version "$numeric_version" --arg hash "$new_hash" '.[$template] = {version: $version, hash: $hash}' "$VERSION_FILE" > "$temp_file" && mv "$temp_file" "$VERSION_FILE"
    else
        jq --arg template "$template_name" --argjson version "$numeric_version" '.[$template] = {version: $version, hash: ""}' "$VERSION_FILE" > "$temp_file" && mv "$temp_file" "$VERSION_FILE"
    fi
}


# Function to copy modules into a temporary template directory (for pushing only)
copy_modules_to_template() {
    local template_dir="$1"
    # Copy modules directly to template root, not subdirectory
    # Terraform only reads .tf files in the root directory
    local modules_dest="$template_dir"
    
    if [[ ! -d "$MODULES_DIR" ]]; then
        >&2 log_warn "Modules directory not found: $MODULES_DIR"
        return 1
    fi
    
    >&2 log "  📦 Bundling modules (temporary, for push only)..."
    
    # Copy all module files directly to template root
    local module_count=0
    for module_file in "$MODULES_DIR"/*.tf; do
        if [[ -f "$module_file" ]]; then
            # Copy to root, not to modules/ subdirectory
            cp "$module_file" "$modules_dest/"
            ((module_count++))
            >&2 log "    ✓ $(basename "$module_file")"
        fi
    done

    # Additionally, copy any module directories into a modules/ subdirectory
    # within the prepared template so module sources like ./modules/name
    # will resolve during Terraform init inside the prepared directory.
    local modules_dir_count=0
    local dest_modules_dir=""
    for module_dir in "$MODULES_DIR"/*/; do
        if [[ -d "$module_dir" ]]; then
            # Lazily create destination modules dir only if we actually have module subdirs
            if [[ $modules_dir_count -eq 0 ]]; then
                dest_modules_dir="$template_dir/modules"
                mkdir -p "$dest_modules_dir"
            fi
            # Copy the entire directory (preserve contents)
            cp -r "$module_dir" "$dest_modules_dir/"
            ((modules_dir_count++))
            >&2 log "    ✓ coped module dir: $(basename "$module_dir")"
        fi
    done

    if [[ $module_count -gt 0 || $modules_dir_count -gt 0 ]]; then
        >&2 log "  ✅ Bundled $module_count module files and $modules_dir_count module dirs to template root"
        return 0
    else
        >&2 log_warn "No module files or directories found to copy"
        return 1
    fi
}

# Function to prepare template directory with modules (temporary, for pushing only)
prepare_template_directory() {
    local source_dir="$1"
    local template_name="$2"
    local prepared_dir="$TEMP_DIR/prepared_${template_name}"
    
    >&2 log "🔧 Preparing temporary template directory: $template_name"
    
    # Create prepared directory in temp location
    mkdir -p "$prepared_dir"
    
    # Copy all template files to temp directory
    cp -r "$source_dir"/* "$prepared_dir/" 2>/dev/null || true
    
    # Copy modules into the temp prepared directory (not the source!)
    copy_modules_to_template "$prepared_dir"
    
    >&2 log "  📂 Template prepared at: $prepared_dir (temporary)"
    
    # Return just the path
    echo "$prepared_dir"
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

# Function to find template files
find_template_files() {
    log "Scanning for template files in $TEMPLATES_DIR..."
    
    local files=()
    
    # Look for template directories with main.tf files (skip _archive, modules, and hidden dirs)
    while IFS= read -r dir; do
        if [[ -f "$dir/main.tf" || -f "$dir/template.tf" ]]; then
            files+=("$dir")
        fi
    done < <(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "_*" ! -name ".*" ! -name "modules" 2>/dev/null)
    
    # If no directories found, look for archive files
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No template directories found, looking for archives..."
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$TEMPLATES_DIR" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.zip" \) -print0 2>/dev/null)
    fi
    
    printf '%s\n' "${files[@]}"
}

# Function to push templates using Coder CLI
push_with_cli() {
    log "Attempting to push templates using Coder CLI..."
    
    # Check if coder CLI is available (either locally or via docker)
    local CODER_CMD=""
    if command -v coder &> /dev/null; then
        CODER_CMD="coder"
        log "Using local Coder CLI"
    elif [ -f "/tmp/coder-cli" ]; then
        CODER_CMD="/tmp/coder-cli"
        log "Using Coder CLI from /tmp/coder-cli"
    elif docker exec coder coder version &> /dev/null 2>&1; then
        # Copy coder binary from container for local use
        log "Copying Coder CLI from Docker container..."
        docker cp coder:/opt/coder /tmp/coder-cli 2>&1 | grep -v "^$" || true
        chmod +x /tmp/coder-cli
        CODER_CMD="/tmp/coder-cli"
        log "Using Coder CLI from Docker container (copied locally)"
    else
        log_warn "Coder CLI not found"
        return 1
    fi
    
    # Set Coder URL
    export CODER_URL="$CODER_URL"
    
    # Check CLI authentication  
    if ! $CODER_CMD templates list &> /dev/null; then
        log_warn "CLI authentication required. Please run: coder login $CODER_URL"
        return 1
    fi
    
    local files
    readarray -t files < <(find_template_files)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No template files found to push"
        return 1
    fi
    
    for file in "${files[@]}"; do
        local basename_file
        basename_file=$(basename "$file")
        local template_name="${basename_file%.*}"  # Remove extension
        template_name="${template_name%_*}"        # Remove timestamp if present
        
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "📤 Pushing template: $template_name"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # We'll determine version_to_use after preparing the template directory
        # because auto-versioning relies on a content hash of the prepared dir.
        local version_to_use="$VERSION"
        
        if [[ -d "$file" ]]; then
            # Directory with Terraform files  
            # Prepare directory with modules
            local prepared_dir
            prepared_dir=$(prepare_template_directory "$file" "$template_name")
            # If auto mode, compute the version based on the prepared directory hash
            if [[ "$VERSION" == "auto" ]]; then
                version_to_use=$(get_next_version "$template_name" "$prepared_dir")
                log "🔢 Auto-incrementing version: $version_to_use"
            elif [[ -n "$VERSION" ]]; then
                log "🔢 Using specified version: $version_to_use"
            fi

            # Push using coder CLI - use collision-resolution when pushing named versions
            push_template_with_collision_resolution "$template_name" "$prepared_dir" "$version_to_use" || true
        else
            # Archive file
            mkdir -p "$TEMP_DIR"
            local extract_dir="$TEMP_DIR/$template_name"
            
            # Extract archive
            case "$file" in
                *.tar.gz|*.tgz)
                    tar -xzf "$file" -C "$TEMP_DIR"
                    ;;
                *.tar)
                    tar -xf "$file" -C "$TEMP_DIR"
                    ;;
                *.zip)
                    unzip -q "$file" -d "$extract_dir"
                    ;;
                *)
                    log_warn "Unsupported file format: $file"
                    continue
                    ;;
            esac
            
            # Find the extracted directory
            local template_dir
            template_dir=$(find "$TEMP_DIR" -name "*.tf" -type f | head -1 | xargs dirname 2>/dev/null || echo "")
            
            if [[ -n "$template_dir" && -d "$template_dir" ]]; then
                # Prepare directory with modules
                local prepared_dir
                prepared_dir=$(prepare_template_directory "$template_dir" "$template_name")
                # If auto mode, compute version using extracted prepared dir
                if [[ "$VERSION" == "auto" ]]; then
                    version_to_use=$(get_next_version "$template_name" "$prepared_dir")
                    log "🔢 Auto-incrementing version from archive: $version_to_use"
                fi

                push_template_with_collision_resolution "$template_name" "$prepared_dir" "$version_to_use" || true
            else
                log_error "❌ Could not find Terraform files in $file"
            fi
        fi
    done
    
    return 0
}

# Helper: push a template and resolve name collisions by retrying with higher vN
push_template_with_collision_resolution() {
    local template_name="$1"
    local prepared_dir="$2"
    local requested_version="$3"  # may be empty

    local attempts=5
    local attempt=0
    local base_version_num
    local push_output

    # Determine highest remote version number to avoid collisions
    remote_highest=$(remote_highest_version "$template_name" 2>/dev/null || echo 0)

    if [[ "$VERSION" == "auto" ]]; then
        # In auto mode, always base on remote state; if no versions exist, start at v1
        base_version_num=$((remote_highest + 1))
        requested_version=""  # ignore any locally suggested version
    else
        if [[ -n "$requested_version" && "$requested_version" =~ ^v([0-9]+)$ ]]; then
            base_version_num=${BASH_REMATCH[1]}
            # If remote already has this or higher, start from remote_highest+1
            if [[ $remote_highest -ge $base_version_num ]]; then
                base_version_num=$((remote_highest + 1))
            fi
        else
            # Start from remote_highest+1 for nameless cases
            base_version_num=$((remote_highest + 1))
        fi
    fi

    while [[ $attempt -lt $attempts ]]; do
        local name_to_try
        if [[ -n "$requested_version" && $attempt -eq 0 ]]; then
            name_to_try="$requested_version"
        else
            name_to_try="v$((base_version_num + attempt))"
        fi

    if [[ -n "$name_to_try" ]]; then
            if push_output=$($CODER_CMD templates push "$template_name" --directory "$prepared_dir" --name "$name_to_try" --yes 2>&1); then
                log "✅ Successfully pushed $template_name ($name_to_try)"
                # Persist the version and computed hash
                if [[ "$VERSION" == "auto" || -n "$requested_version" ]]; then
                    save_version "$template_name" "$name_to_try" "$prepared_dir"
                fi
                return 0
            else
                # Detect name collision from Coder error output
                if echo "$push_output" | grep -qi "already exists"; then
                    log_warn "Version name $name_to_try already exists, retrying with v$((base_version_num + attempt + 1))..."
                    ((attempt++))
                    continue
                else
                    log_error "❌ Failed to push template $template_name"
                    log_error "Output: $push_output"
                    return 1
                fi
            fi
        else
            # Push without name
            if push_output=$($CODER_CMD templates push "$template_name" --directory "$prepared_dir" --yes 2>&1); then
                log "✅ Successfully pushed $template_name"
                return 0
            else
                log_error "❌ Failed to push template $template_name"
                log_error "Output: $push_output"
                return 1
            fi
        fi
    done

    log_error "❌ Exhausted retries for template $template_name; last attempted $name_to_try"
    return 1
}

# Query remote Coder for existing template versions and return highest numeric suffix
remote_highest_version() {
    local template_name="$1"
    # Try JSON output first (if CLI supports it)
    if push_output=$($CODER_CMD templates versions list "$template_name" --json 2>/dev/null); then
        # Parse JSON for names like v123
        echo "$push_output" | jq -r '.[].name' 2>/dev/null | grep -E '^v[0-9]+$' | sed 's/^v//' | sort -n | tail -1 || echo 0
        return 0
    fi

    # Fallback to plain text parsing
    if push_output=$($CODER_CMD templates versions list "$template_name" 2>/dev/null); then
        echo "$push_output" | grep -Eo 'v[0-9]+' | sed 's/^v//' | sort -n | tail -1 || echo 0
        return 0
    fi

    echo 0
}

# Function to show manual instructions
show_manual_instructions() {
    log_warn "Automatic push failed. Manual steps required:"
    echo ""
    echo -e "${BLUE}📋 Manual Template Upload Instructions:${NC}"
    echo "1. Open Coder UI: $CODER_URL"
    echo "2. Navigate to Templates section"
    echo "3. Click 'Create Template' or 'Upload Template'"
    echo "4. Upload the template files from: $TEMPLATES_DIR"
    echo ""
    echo -e "${BLUE}📁 Available template files:${NC}"
    
    local files
    readarray -t files < <(find_template_files)
    
    for file in "${files[@]}"; do
        echo "  $(basename "$file")"
    done
}

# Function to create a deployment manifest (optional, in temp directory)
create_deployment_manifest() {
    # Skip manifest creation to avoid cluttering directories
    # Uncomment below if you want manifests in temp directory
    return 0
    
    # log "Creating deployment manifest..."
    # 
    # local manifest_file="$TEMP_DIR/deployment_manifest_$(date +"%Y%m%d_%H%M%S").txt"
    # 
    # cat > "$manifest_file" << EOF
# # Coder Templates Deployment Manifest
# # Generated: $(date)
# # Target: $CODER_URL
# # Source Directory: $TEMPLATES_DIR
# 
# Templates to deploy:
# EOF
    # 
    # local files
    # readarray -t files < <(find_template_files)
    # 
    # for file in "${files[@]}"; do
    #     echo "  $(basename "$file")" >> "$manifest_file"
    # done
    # 
    # log "✅ Deployment manifest created: $manifest_file"
}

# Main execution
main() {
    log "🚀 Starting Coder templates push..."
    log "Target: $CODER_URL"
    log "Source: $TEMPLATES_DIR"
    log "Modules: $MODULES_DIR"
    
    # Check if templates directory exists
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log_error "Templates directory not found: $TEMPLATES_DIR"
        exit 1
    fi
    
    # Check if modules directory exists
    if [[ ! -d "$MODULES_DIR" ]]; then
        log_warn "Modules directory not found: $MODULES_DIR"
        log_warn "Templates will be pushed without modules"
    else
        local module_count
        module_count=$(find "$MODULES_DIR" -name "*.tf" -type f | wc -l)
        log "📦 Found $module_count module files to include"
    fi
    
    # Check if Coder is accessible
    if ! check_coder_access; then
        exit 1
    fi
    
    # Create deployment manifest
    create_deployment_manifest
    
    # Try to push templates
    if push_with_cli; then
        log "✅ Templates pushed successfully using Coder CLI"
    else
        show_manual_instructions
    fi
    
    # Cleanup temporary files
    if [[ -d "$TEMP_DIR" ]]; then
        log "🧹 Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
    
    log "🎉 Push process completed!"
    log ""
    log "Note: Local template directories remain unchanged."
    log "      Modules were bundled temporarily only for pushing."
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Coder Templates Push Script"
    echo ""
    echo "Usage: $0 [CODER_URL] [TEMPLATES_DIR]"
    echo ""
    echo "Arguments:"
    echo "  CODER_URL      URL of target Coder instance (default: http://localhost:7080)"
    echo "  TEMPLATES_DIR  Directory containing templates (default: ./templates)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Push to localhost from ./templates"
    echo "  $0 http://coder.example.com ./backup # Push to remote from ./backup"
    echo ""
    echo "Features:"
    echo "  - Bundles module files from ../modules/ with each template during push"
    echo "  - Modules are only combined temporarily and NOT copied to local templates"
    echo "  - Local template directories stay clean with only main template files"
    echo "  - Supports .tar, .tar.gz, .zip archives and directory-based templates"
    echo ""
    echo "Workflow:"
    echo "  1. Keep templates minimal in templates/ directory (just main.tf, etc.)"
    echo "  2. Keep reusable modules in modules/ directory"
    echo "  3. Script temporarily combines them when pushing to Coder"
    echo "  4. Local files remain unchanged after push completes"
    echo ""
    echo "Directory Structure:"
    echo "  config/coder/"
    echo "    ├── templates/            # Template and module directories"
    echo "    │   ├── modules/          # Shared module files (*.tf)"
    echo "    │   │   ├── init-shell.tf"
    echo "    │   │   ├── install-docker.tf"
    echo "    │   │   └── ..."
    echo "    │   └── my-template/"     # Clean template directories"
    echo "    │       └── main.tf       # References modules via local path"
    echo "    └── scripts/"
    echo "        └── push-templates.sh # This script"
    echo ""
    exit 0
fi

# Run main function
main "$@"
