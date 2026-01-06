#!/bin/bash
# =============================================================================
# SIMPLE VERSIONED TEMPLATE PUSH
# =============================================================================
# Pushes a template with incremental version naming (v1, v2, v3...)
#
# Usage:
#   ./push-template-versioned.sh [--dry-run] [--ref <ref>] [--fallback <ref>] <template-name>
#
# Flags:
#   --dry-run         Show resolved ref and intended substitutions; do not push
#   --ref <ref>       Override auto-detected ref (e.g., v0.1.1, main, feature/x)
#   --fallback <ref>  Fallback ref if detected ref not found on remote (default: main)
#
# Example:
#   ./push-template-versioned.sh docker-workspace
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $1"; }
log_error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }

# -----------------------------------------------------------------------------
# Argument parsing & defaults
# -----------------------------------------------------------------------------
DRY_RUN=false
REF_OVERRIDE="${REF_OVERRIDE:-}"
FALLBACK_REF="${FALLBACK_REF:-main}"

ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --ref)
            REF_OVERRIDE="${2:-}"
            shift 2
            ;;
        --fallback)
            FALLBACK_REF="${2:-main}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--ref <ref>] [--fallback <ref>] <template-name>"
            exit 0
            ;;
        --)
            shift; break
            ;;
        -*)
            log_error "Unknown flag: $1"
            exit 1
            ;;
        *)
            ARGS+=("$1"); shift
            ;;
    esac
done

set +u
TEMPLATE_NAME="${ARGS[0]}"
set -u

# Configuration
TEMPLATES_DIR="$(dirname "$0")/../templates"
VERSION_FILE="$(dirname "$0")/.template_versions.json"
SHARED_PARAMS_DIR="$(dirname "$0")/../template-modules/params"
MODULES_DIR="$(dirname "$0")/../template-modules/modules"

# Source .env file for BASE_DOMAIN and other configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$WORKSPACE_ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
    log "Loading environment from $ENV_FILE"
    # Use export to safely load only variable assignments, skip comments and blank lines
    set -a  # automatically export all variables
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        # Export valid variable assignments
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            export "$line"
        fi
    done < "$ENV_FILE"
    set +a
else
    log_warn ".env file not found at $ENV_FILE - using defaults"
fi

if [[ -z "$TEMPLATE_NAME" ]]; then
    log_error "Usage: $0 <template-name>"
    log_error "Available templates:"
    ls -1 "$TEMPLATES_DIR" | grep -v "^git-modules$" | grep -v "^_" | sed 's/^/  /'
    exit 1
fi

TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    log_error "Template directory not found: $TEMPLATE_DIR"
    exit 1
fi

# -----------------------------------------------------------------------------
# Git ref detection & validation
# -----------------------------------------------------------------------------
detect_git_ref() {
    # Priority: explicit override > exact tag (v*) > main branch > current branch name
    if [[ -n "${REF_OVERRIDE}" ]]; then
        echo "${REF_OVERRIDE}"
        return 0
    fi

    # Exact tag? prefer semver-like tags
    if TAG=$(git describe --tags --exact-match 2>/dev/null); then
        if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
            echo "$TAG"; return 0
        fi
    fi

    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    if [[ "$BRANCH" == "main" ]]; then
        echo "main"; return 0
    fi

    if [[ "$BRANCH" != "HEAD" ]]; then
        echo "$BRANCH"; return 0
    fi

    # Detached HEAD without tag: fallback
    echo "$FALLBACK_REF"
}

validate_remote_ref() {
    local ref="$1"
    if git ls-remote --exit-code origin "$ref" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

url_encode_ref() {
    # Minimal encode: replace '/' with '%2F' to keep query param valid
    local ref="$1"
    echo "${ref//\//%2F}"
}

# Get next version number from modules.txt VERSION line
get_next_version() {
    local template_dir="$1"
    local modules_file="$template_dir/modules.txt"
    
    if [[ ! -f "$modules_file" ]]; then
        echo "1"
        return
    fi
    
    # Extract version from "# VERSION: X" line
    local current_version=$(grep -E "^# VERSION:" "$modules_file" | sed -E 's/^# VERSION:\s*//' | tr -d '[:space:]')
    
    # Default to 0 if VERSION line is missing or empty
    if [[ -z "$current_version" ]]; then
        echo "1"
        return
    fi
    
    echo $((current_version + 1))
}

# Save version number to modules.txt VERSION line
save_version() {
    local template_dir="$1"
    local version="$2"
    local modules_file="$template_dir/modules.txt"
    
    if [[ -f "$modules_file" ]]; then
        # Check if VERSION line exists
        if grep -q "^# VERSION:" "$modules_file"; then
            # Update existing VERSION line
            sed -i "s/^# VERSION:.*$/# VERSION: $version/" "$modules_file"
        else
            # Add VERSION line after first comment block (line 4)
            sed -i "4i# VERSION: $version" "$modules_file"
        fi
        log "📝 Saved version $version to $modules_file"
    else
        log_warn "No modules.txt found, version not saved"
    fi
}

# Determine next available version name by checking both local counter and remote versions
VERSION_NUM=$(get_next_version "$TEMPLATE_DIR")

# Query remote existing versions and find max; if remote has higher/equal, bump
if docker exec coder coder templates versions list "$TEMPLATE_NAME" >/tmp/_versions.txt 2>/dev/null; then
    # Extract numeric suffixes like v12 -> 12
    REMOTE_MAX=$(sed -e 's/\x1b\[[0-9;]*m//g' /tmp/_versions.txt | awk 'NR>1 {print $1}' | sed 's/^v//' | sort -n | tail -1)
    if [[ -n "$REMOTE_MAX" ]]; then
        if (( REMOTE_MAX >= VERSION_NUM )); then
            VERSION_NUM=$((REMOTE_MAX + 1))
        fi
    fi
fi

VERSION_NAME="v${VERSION_NUM}"

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "📤 Pushing Template: $TEMPLATE_NAME"
log "🔢 Version: $VERSION_NAME"

# Resolve git ref
RESOLVED_REF=$(detect_git_ref)
if validate_remote_ref "$RESOLVED_REF"; then
    log "🔗 Resolved git ref: $RESOLVED_REF (validated on origin)"
else
    log_warn "Ref '$RESOLVED_REF' not found on origin; using fallback '$FALLBACK_REF'"
    if ! validate_remote_ref "$FALLBACK_REF"; then
        log_error "Fallback ref '$FALLBACK_REF' not found on origin. Aborting."
        exit 1
    fi
    RESOLVED_REF="$FALLBACK_REF"
fi
ENC_REF=$(url_encode_ref "$RESOLVED_REF")
log "🔐 Encoded ref for URL: $ENC_REF"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy template to temp directory
TEMP_DIR="/tmp/coder-push-$$"
mkdir -p "$TEMP_DIR"
cp -r "$TEMPLATE_DIR" "$TEMP_DIR/$TEMPLATE_NAME"

# Overlay shared params (do not override if file already exists in template)
# SKIP overlay if modules.txt exists (new declarative system)
overlay_shared_params() {
    local shared_dir="$1"
    local dest_dir="$2"
    
    # Skip overlay if template uses new modules.txt system
    if [[ -f "$dest_dir/modules.txt" ]]; then
        log "📋 modules.txt found - using declarative module system (skipping overlay)"
        return 0
    fi
    
    if [[ ! -d "$shared_dir" ]]; then
        log_warn "Shared params dir not found: $shared_dir (skipping overlay)"
        return 0
    fi
    local count=0
    for f in "$shared_dir"/*-params.tf; do
        [[ -e "$f" ]] || continue
        local base
        base=$(basename "$f")
        if [[ -f "$dest_dir/$base" ]]; then
            log_warn "Skip overlay (template override present): $base"
            continue
        fi
        cp "$f" "$dest_dir/$base"
        count=$((count+1))
    done
    log "📦 Overlay applied: $count shared param file(s) copied"
}

overlay_shared_params "$SHARED_PARAMS_DIR" "$TEMP_DIR/$TEMPLATE_NAME"

# Copy modules from modules.txt (new declarative system)
copy_modules_from_manifest() {
    local template_dir="$1"
    local dest_dir="$2"
    local modules_file="$template_dir/modules.txt"
    
    if [[ ! -f "$modules_file" ]]; then
        return 0
    fi
    
    log "📋 Processing modules from modules.txt..."
    local count=0
    
    # Read modules.txt and process each module line
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Strip inline comments and whitespace
        local module_file
        module_file=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$module_file" ]] && continue
        
        # Check if module already exists in template dir (local override)
        if [[ -f "$template_dir/$module_file" ]]; then
            log "  ✓ Using local override: $module_file"
            count=$((count+1))
            continue
        fi
        
        # Copy from shared params directory
        local shared_module="$SHARED_PARAMS_DIR/$module_file"
        if [[ -f "$shared_module" ]]; then
            cp "$shared_module" "$dest_dir/$module_file"
            log "  ✓ Copied from shared: $module_file"
            count=$((count+1))
        else
            log_error "Module not found: $module_file (not in template or shared params)"
            exit 1
        fi
    done < "$modules_file"
    
    log "📦 Modules copied: $count module(s) from modules.txt"
}

# Extract metadata from modules
extract_metadata_from_modules() {
    local template_dir="$1"
    local modules_file="$template_dir/modules.txt"
    
    if [[ ! -f "$modules_file" ]]; then
        return 0
    fi
    
    local -a metadata_options=()
    
    # Read modules.txt and check each module for metadata_blocks output
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Strip inline comments and whitespace to get module filename
        local module_file
        module_file=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$module_file" ]] && continue
        
        # Skip metadata-params.tf itself
        [[ "$module_file" == "metadata-params.tf" ]] && continue
        
        # Convert param filename to module name (e.g., docker-params.tf -> docker-module)
        local module_name
        module_name=$(echo "$module_file" | sed 's/-params\.tf$/-module/')
        
        # Check if module exists and has metadata_blocks output
        local module_path="$MODULES_DIR/$module_name/main.tf"
        if [[ ! -f "$module_path" ]]; then
            continue
        fi
        
        # Extract metadata_blocks output value
        # Look for: output "metadata_blocks" { ... value = [...] }
        local metadata_content
        metadata_content=$(sed -n '/output "metadata_blocks"/,/^}/p' "$module_path")
        
        # Check if value is empty array
        if echo "$metadata_content" | grep -q 'value[[:space:]]*=[[:space:]]*\[\]'; then
            continue  # Skip modules with empty metadata
        fi
        
        # Check if value has at least one metadata block
        if ! echo "$metadata_content" | grep -q 'display_name'; then
            continue  # No metadata blocks found
        fi
        
        # Extract display_name from first metadata block
        local display_name
        display_name=$(echo "$metadata_content" | grep -m1 'display_name' | sed -E 's/.*display_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
        
        if [[ -z "$display_name" ]]; then
            continue
        fi
        
        # Convert display_name to snake_case identifier
        local identifier
        identifier=$(echo "$display_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
        
        # Store as "identifier|display_name|module_name"
        metadata_options+=("$identifier|$display_name|$module_name")
    done < "$modules_file"
    
    # Return array as newline-separated string
    printf '%s\n' "${metadata_options[@]}"
}

# Generate metadata-params.tf file
generate_metadata_params_file() {
    local dest_dir="$1"
    shift  # Remove dest_dir from args
    local -a metadata_options=("$@")
    
    local output_file="$dest_dir/metadata-params.tf"
    
    # Count module-contributed metadata
    local module_count=${#metadata_options[@]}
    
    cat > "$output_file" <<'EOF'
# =============================================================================
# METADATA PARAMETERS - AUTO-GENERATED
# =============================================================================
# THIS FILE IS AUTO-GENERATED by push-template-versioned.sh
# Do not edit manually - changes will be overwritten on next push
#
# Metadata options are sourced from:
#   - Core built-in blocks (cpu, ram, disk, etc.)
#   - Active modules that provide metadata_blocks output
# =============================================================================

data "coder_parameter" "metadata_blocks" {
  name         = "metadata_blocks"
  display_name = "Metadata Blocks"
  description  = "Select metadata blocks to display in the workspace."
  type         = "list(string)"
  form_type    = "multi-select"
  default      = jsonencode([])
  mutable      = true
  order        = 50

  # Core metadata blocks (always available)
  option {
    name  = "CPU"
    value = "cpu"
  }
  option {
    name  = "RAM"
    value = "ram"
  }
  option {
    name  = "Disk"
    value = "disk"
  }
  option {
    name  = "Architecture"
    value = "arch"
  }
  option {
    name  = "Validation"
    value = "validation"
  }
  option {
    name  = "Load Average"
    value = "load_avg"
  }
  option {
    name  = "Uptime"
    value = "uptime"
  }
  option {
    name  = "SSH Port"
    value = "ssh_port"
  }
EOF

    # Add module-contributed metadata options
    for opt in "${metadata_options[@]}"; do
        [[ -z "$opt" ]] && continue
        
        # Parse "identifier|display_name|module_name"
        local identifier display_name module_name
        IFS='|' read -r identifier display_name module_name <<< "$opt"
        
        cat >> "$output_file" <<EOF

  # From $module_name
  option {
    name  = "$display_name"
    value = "$identifier"
  }
EOF
    done
    
    # Close the parameter block
    echo "}" >> "$output_file"
    
    log "🏷️  Generated metadata-params.tf with $((8 + module_count)) options (8 core + $module_count from modules)"
}

copy_modules_from_manifest "$TEMPLATE_DIR" "$TEMP_DIR/$TEMPLATE_NAME"

# Extract and generate metadata-params.tf
mapfile -t METADATA_OPTIONS < <(extract_metadata_from_modules "$TEMPLATE_DIR")
generate_metadata_params_file "$TEMP_DIR/$TEMPLATE_NAME" "${METADATA_OPTIONS[@]}"

# Substitute ref in temp .tf files for this repository's git module sources
substitute_ref_in_temp() {
    local root="$1"
    local -a files
    # Limit to Terraform files referencing this repo
    mapfile -t files < <(grep -RIl --include='*.tf' 'git::https://github.com/weekend-code-project/weekendstack.git' "$root" || true)
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No weekendstack git module sources found to rewrite in $root"
        return 0
    fi
    for f in "${files[@]}"; do
        # Replace existing ?ref= value with resolved ref
        sed -E -i "s|(git::https://github.com/weekend-code-project/weekendstack.git//[^?]+\?ref=)[^\"]+|\1${ENC_REF}|g" "$f"
    done
    log "✏️  Updated ref to '$RESOLVED_REF' in ${#files[@]} file(s)."
}

# Substitute base_domain default value in variables.tf
substitute_base_domain() {
    local root="$1"
    local domain="${BASE_DOMAIN:-localhost}"
    
    # Find variables.tf files that have base_domain variable
    local -a files
    mapfile -t files < <(grep -l 'variable "base_domain"' "$root"/*.tf 2>/dev/null || true)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warn "No base_domain variable found in $root"
        return 0
    fi
    
    for f in "${files[@]}"; do
        log "  📝 Updating base_domain in: $(basename "$f")"
        # Replace the default value for base_domain variable
        # Matches: default = "anything"
        # Replaces with: default = "$domain"
        sed -i "/variable \"base_domain\"/,/^}/ s|default[[:space:]]*=[[:space:]]*\"[^\"]*\"|default     = \"$domain\"|" "$f"
        # Verify the change
        if grep -q "default.*=.*\"$domain\"" "$f"; then
            log "  ✓ Verified: $domain set in $(basename "$f")"
        else
            log_warn "  ✗ Warning: substitution may have failed in $(basename "$f")"
        fi
    done
    
    log "✏️  Updated base_domain default to '$domain' in ${#files[@]} file(s)."
}

# Substitute host_ip default value in variables.tf
substitute_host_ip() {
    local root="$1"
    local ip="${HOST_IP:-localhost}"
    
    # Find variables.tf files that have host_ip variable
    local -a files
    mapfile -t files < <(grep -l 'variable "host_ip"' "$root"/*.tf 2>/dev/null || true)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        # Not a warning - host_ip is optional
        return 0
    fi
    
    for f in "${files[@]}"; do
        log "  📝 Updating host_ip in: $(basename "$f")"
        sed -i "/variable \"host_ip\"/,/^}/ s|default[[:space:]]*=[[:space:]]*\"[^\"]*\"|default     = \"$ip\"|" "$f"
        if grep -q "default.*=.*\"$ip\"" "$f"; then
            log "  ✓ Verified: $ip set in $(basename "$f")"
        else
            log_warn "  ✗ Warning: substitution may have failed in $(basename "$f")"
        fi
    done
    
    log "✏️  Updated host_ip default to '$ip' in ${#files[@]} file(s)."
}


DRY_RUN_PREVIEW() {
    local root="$1"
    log "🔍 Dry run preview: showing lines with '?ref=' before substitution"
    grep -Rn --include='*.tf' '\?ref=' "$root" || true
}

# If dry-run, preview before and after substitution and exit
if $DRY_RUN; then
    log "(dry-run) Template staging dir: $TEMP_DIR/$TEMPLATE_NAME"
    DRY_RUN_PREVIEW "$TEMP_DIR/$TEMPLATE_NAME"
    substitute_ref_in_temp "$TEMP_DIR/$TEMPLATE_NAME"
    substitute_base_domain "$TEMP_DIR/$TEMPLATE_NAME"
    substitute_host_ip "$TEMP_DIR/$TEMPLATE_NAME"
    log "🔍 Dry run preview: showing lines with '?ref=' after substitution"
    grep -Rn --include='*.tf' '\?ref=' "$TEMP_DIR/$TEMPLATE_NAME" || true
    log "🔍 Dry run preview: showing base_domain after substitution"
    grep -A4 'variable "base_domain"' "$TEMP_DIR/$TEMPLATE_NAME"/*.tf || true
    log "🔍 Dry run preview: showing host_ip after substitution"
    grep -A4 'variable "host_ip"' "$TEMP_DIR/$TEMPLATE_NAME"/*.tf || true
    if [[ -f "$TEMP_DIR/$TEMPLATE_NAME/metadata-params.tf" ]]; then
        log "🔍 Dry run preview: showing generated metadata-params.tf"
        cat "$TEMP_DIR/$TEMPLATE_NAME/metadata-params.tf"
    fi
    log "✅ Dry run complete. No changes pushed."
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Perform substitution for actual push
substitute_ref_in_temp "$TEMP_DIR/$TEMPLATE_NAME"
substitute_base_domain "$TEMP_DIR/$TEMPLATE_NAME"
substitute_host_ip "$TEMP_DIR/$TEMPLATE_NAME"

# Verify substitution before push
log "🔍 Final verification before push:"
if [[ -f "$TEMP_DIR/$TEMPLATE_NAME/variables.tf" ]]; then
    BASE_DOMAIN_VALUE=$(grep -A5 'variable "base_domain"' "$TEMP_DIR/$TEMPLATE_NAME/variables.tf" | grep 'default' | head -1 | sed -E 's/.*"(.*)".*/\1/')
    log "  base_domain in variables.tf: '$BASE_DOMAIN_VALUE'"
else
    log_warn "  variables.tf not found!"
fi

# Push using docker exec
log "Copying template to Coder container..."
docker cp "$TEMP_DIR/$TEMPLATE_NAME" coder:/tmp/

# Verify after copy to container
log "🔍 Verifying in Coder container after copy:"
docker exec coder sh -c "grep -A3 'variable \"base_domain\"' /tmp/$TEMPLATE_NAME/variables.tf | grep 'default'" || log_warn "Could not verify in container"

log "Pushing template..."
MAX_RETRIES=5
RETRY_COUNT=0

# (Coder CLI version does not support --icon flag; icon.svg retained for future use)

# Pass core vars as TF_VAR values so Terraform plans capture the real host paths/IPs
PUSH_ENV_VARS="-e TF_VAR_base_domain=${BASE_DOMAIN:-localhost}"
PUSH_ENV_VARS+=" -e TF_VAR_host_ip=${HOST_IP:-127.0.0.1}"
PUSH_ENV_VARS+=" -e TF_VAR_ssh_key_dir=${SSH_KEY_DIR:-/home/docker/.ssh}"
PUSH_ENV_VARS+=" -e TF_VAR_traefik_auth_dir=${TRAEFIK_AUTH_DIR:-/opt/stacks/weekendstack/config/traefik/auth}"
log "Setting TF_VAR_base_domain=${BASE_DOMAIN:-localhost}"
log "Setting TF_VAR_host_ip=${HOST_IP:-127.0.0.1}"
log "Setting TF_VAR_ssh_key_dir=${SSH_KEY_DIR:-/home/docker/.ssh}"
log "Setting TF_VAR_traefik_auth_dir=${TRAEFIK_AUTH_DIR:-/opt/stacks/weekendstack/config/traefik/auth}"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec $PUSH_ENV_VARS coder coder templates push "$TEMPLATE_NAME" \
        --directory "/tmp/$TEMPLATE_NAME" \
        --name "$VERSION_NAME" \
        --yes 2>&1 | tee /tmp/push-output.txt; then
        
        log "✅ Successfully pushed $TEMPLATE_NAME ($VERSION_NAME)"
        save_version "$TEMPLATE_DIR" "$VERSION_NUM"
        
    # Cleanup
        rm -rf "$TEMP_DIR"
        docker exec coder rm -rf "/tmp/$TEMPLATE_NAME"
        
        log "🎉 Complete! Template available as: $TEMPLATE_NAME ($VERSION_NAME)"
        exit 0
    else
        # Check if it's a duplicate version error
        if grep -q "already exists" /tmp/push-output.txt; then
            RETRY_COUNT=$((RETRY_COUNT + 1))
            VERSION_NUM=$((VERSION_NUM + 1))
            VERSION_NAME="v${VERSION_NUM}"
            log_warn "Version already exists, retrying with $VERSION_NAME (attempt $RETRY_COUNT/$MAX_RETRIES)"
            # Persist the bumped version to the temp directory path inside coder container
            true
        else
            log_error "❌ Failed to push template (non-version error)"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    fi
done

log_error "❌ Failed to push template after $MAX_RETRIES attempts"
rm -rf "$TEMP_DIR"
exit 1
