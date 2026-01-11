#!/bin/bash
# =============================================================================
# CODER TEMPLATE PUSH SCRIPT v2
# =============================================================================
# A simplified push script for the new modular template system.
# 
# Key differences from v1:
#   - No auto-copy of modules - templates are self-contained
#   - Compiles startup scripts from module partials
#   - Manifest-driven module composition
#   - Variable substitution for base_domain, host_ip
#
# Usage:
#   ./push-template.sh [--dry-run] [--name <version-name>] <template-name>
#
# Examples:
#   ./push-template.sh base                    # Push with auto-versioned name
#   ./push-template.sh --dry-run base          # Preview without pushing
#   ./push-template.sh --name v1 base          # Push with specific version name
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$V2_ROOT/templates"
MODULES_DIR="$V2_ROOT/modules"
HELPERS_DIR="$V2_ROOT/helpers"
DIST_DIR="$V2_ROOT/dist"

# Find workspace root and load .env
# v2 is at: /opt/stacks/weekendstack/config/coder/v2
# .env is at: /opt/stacks/weekendstack/.env
WORKSPACE_ROOT="$(cd "$V2_ROOT/../../.." && pwd)"
ENV_FILE="$WORKSPACE_ROOT/.env"

# =============================================================================
# Colors & Logging
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()       { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
log_info()  { echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️${NC}  $1"; }
log_error() { echo -e "${RED}[$(date +'%H:%M:%S')] ❌${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅${NC} $1"; }

# =============================================================================
# Argument Parsing
# =============================================================================

DRY_RUN=false
VERSION_NAME=""
TEMPLATE_NAME=""

print_usage() {
    echo "Usage: $0 [--dry-run] [--name <version-name>] <template-name>"
    echo ""
    echo "Options:"
    echo "  --dry-run          Preview changes without pushing"
    echo "  --name <name>      Specify version name (default: auto-increment)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Available templates:"
    if [[ -d "$TEMPLATES_DIR" ]]; then
        ls -1 "$TEMPLATES_DIR" 2>/dev/null | grep -v "^_" | sed 's/^/  /'
    else
        echo "  (no templates directory found)"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --name)
            VERSION_NAME="${2:-}"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            TEMPLATE_NAME="$1"
            shift
            ;;
    esac
done

if [[ -z "$TEMPLATE_NAME" ]]; then
    log_error "Template name required"
    print_usage
    exit 1
fi

# =============================================================================
# Load Environment
# =============================================================================

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Loading environment from $ENV_FILE"
        set -a
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                export "$line"
            fi
        done < "$ENV_FILE"
        set +a
    else
        log_warn "No .env file found at $ENV_FILE - using defaults"
    fi
    
    # Set defaults
    BASE_DOMAIN="${BASE_DOMAIN:-localhost}"
    HOST_IP="${HOST_IP:-127.0.0.1}"
    SSH_KEY_DIR="${SSH_KEY_DIR:-/home/docker/.ssh}"
    TRAEFIK_AUTH_DIR="${TRAEFIK_AUTH_DIR:-/opt/stacks/weekendstack/config/traefik/auth}"
}

# =============================================================================
# Version Management
# =============================================================================

get_next_version() {
    local template_name="$1"
    local version_file="$V2_ROOT/.versions.json"
    
    # Get current version from local file
    local local_version=0
    if [[ -f "$version_file" ]]; then
        local_version=$(jq -r ".\"$template_name\" // 0" "$version_file" 2>/dev/null || echo "0")
    fi
    
    # Get max version from Coder (if template exists)
    local remote_version=0
    if docker exec coder coder templates versions list "$template_name" >/tmp/_versions.txt 2>/dev/null; then
        remote_version=$(sed -e 's/\x1b\[[0-9;]*m//g' /tmp/_versions.txt | awk 'NR>1 {print $1}' | sed 's/^v//' | sort -n | tail -1)
        remote_version="${remote_version:-0}"
    fi
    
    # Use whichever is higher + 1
    local max_version=$((local_version > remote_version ? local_version : remote_version))
    echo $((max_version + 1))
}

save_version() {
    local template_name="$1"
    local version="$2"
    local version_file="$V2_ROOT/.versions.json"
    
    if [[ ! -f "$version_file" ]]; then
        echo "{}" > "$version_file"
    fi
    
    # Update version in file
    local tmp=$(mktemp)
    jq ".\"$template_name\" = $version" "$version_file" > "$tmp" && mv "$tmp" "$version_file"
    log_info "Saved version $version for $template_name"
}

# =============================================================================
# Template Processing
# =============================================================================

TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME"

validate_template() {
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        log_error "Template not found: $TEMPLATE_DIR"
        echo ""
        print_usage
        exit 1
    fi
    
    if [[ ! -f "$TEMPLATE_DIR/main.tf" ]]; then
        log_error "Template missing main.tf: $TEMPLATE_DIR"
        exit 1
    fi
    
    log_success "Template validated: $TEMPLATE_NAME"
}

# Substitute variables in Terraform files
substitute_variables() {
    local target_dir="$1"
    
    log_info "Substituting variables..."
    
    # Substitute base_domain
    find "$target_dir" -name "*.tf" -type f | while read -r file; do
        if grep -q 'variable "base_domain"' "$file"; then
            sed -i "/variable \"base_domain\"/,/^}/ s|default[[:space:]]*=[[:space:]]*\"[^\"]*\"|default     = \"$BASE_DOMAIN\"|" "$file"
            log_info "  Updated base_domain in $(basename "$file")"
        fi
        
        if grep -q 'variable "host_ip"' "$file"; then
            sed -i "/variable \"host_ip\"/,/^}/ s|default[[:space:]]*=[[:space:]]*\"[^\"]*\"|default     = \"$HOST_IP\"|" "$file"
            log_info "  Updated host_ip in $(basename "$file")"
        fi
    done
}

# Compile startup script from module partials (if manifest exists)
compile_startup_script() {
    local target_dir="$1"
    local manifest_file="$TEMPLATE_DIR/manifest.json"
    
    # Skip if no manifest (simple template)
    if [[ ! -f "$manifest_file" ]]; then
        log_info "No manifest.json - skipping startup compilation"
        return 0
    fi
    
    log_info "Compiling startup script from manifest..."
    
    local generated_dir="$target_dir/generated"
    mkdir -p "$generated_dir"
    
    local startup_file="$generated_dir/startup.sh"
    
    # Write header with helper library
    cat > "$startup_file" <<'STARTUP_HEADER'
#!/bin/bash
# =============================================================================
# COMPILED STARTUP SCRIPT
# =============================================================================
# Generated by push-template.sh - DO NOT EDIT
# This script orchestrates module startup functions in the correct order.
# =============================================================================

# Logging helper
wcp_log() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        INFO)  echo "[${timestamp}] ℹ️  $msg" ;;
        WARN)  echo "[${timestamp}] ⚠️  $msg" ;;
        ERROR) echo "[${timestamp}] ❌ $msg" ;;
        OK)    echo "[${timestamp}] ✅ $msg" ;;
        *)     echo "[${timestamp}] $msg" ;;
    esac
}

# Run a step function only once (idempotent)
wcp_run_once() {
    local step_name="$1"
    local sentinel_dir="${HOME}/.wcp/steps"
    local sentinel_file="${sentinel_dir}/${step_name}.done"
    
    mkdir -p "$sentinel_dir"
    
    if [[ -f "$sentinel_file" ]]; then
        wcp_log INFO "Skipping $step_name (already completed)"
        return 0
    fi
    
    wcp_log INFO "Running $step_name..."
    if "$step_name"; then
        touch "$sentinel_file"
        wcp_log OK "$step_name completed"
        return 0
    else
        wcp_log ERROR "$step_name failed"
        return 1
    fi
}

# =============================================================================
# MODULE FUNCTIONS
# =============================================================================

STARTUP_HEADER

    # Read modules from manifest and collect startup partials
    local modules
    modules=$(jq -r '.modules[]' "$manifest_file" 2>/dev/null || echo "")
    
    local module_functions=()
    
    for module in $modules; do
        local module_path="$MODULES_DIR/$module"
        local partial_file="$module_path/scripts/startup.part.sh"
        
        if [[ -f "$partial_file" ]]; then
            local func_name="wcp__mod_$(echo "$module" | tr '/' '_' | tr '-' '_')"
            
            echo "" >> "$startup_file"
            echo "# --- Module: $module ---" >> "$startup_file"
            echo "$func_name() {" >> "$startup_file"
            cat "$partial_file" >> "$startup_file"
            echo "" >> "$startup_file"
            echo "}" >> "$startup_file"
            
            module_functions+=("$func_name")
            log_info "  Added startup partial: $module"
        fi
    done
    
    # Write main orchestrator
    cat >> "$startup_file" <<'STARTUP_MAIN'

# =============================================================================
# MAIN ORCHESTRATOR
# =============================================================================

main() {
    wcp_log INFO "🚀 Starting workspace initialization..."
    
STARTUP_MAIN

    # Add function calls in order
    for func in "${module_functions[@]}"; do
        echo "    wcp_run_once $func" >> "$startup_file"
    done
    
    cat >> "$startup_file" <<'STARTUP_FOOTER'
    
    wcp_log OK "🎉 Workspace ready!"
}

# Run main
main "$@"
STARTUP_FOOTER

    chmod +x "$startup_file"
    log_success "Compiled startup script: $startup_file"
}

# =============================================================================
# Push to Coder
# =============================================================================

push_to_coder() {
    local temp_dir="$1"
    local version="$2"
    
    log_info "Copying template to Coder container..."
    docker cp "$temp_dir" "coder:/tmp/${TEMPLATE_NAME}-push"
    
    log_info "Pushing template..."
    
    # Set environment variables for Terraform
    local push_env_vars="-e TF_VAR_base_domain=$BASE_DOMAIN"
    push_env_vars+=" -e TF_VAR_host_ip=$HOST_IP"
    push_env_vars+=" -e TF_VAR_ssh_key_dir=$SSH_KEY_DIR"
    push_env_vars+=" -e TF_VAR_traefik_auth_dir=$TRAEFIK_AUTH_DIR"
    
    if docker exec $push_env_vars coder coder templates push "$TEMPLATE_NAME" \
        --directory "/tmp/${TEMPLATE_NAME}-push" \
        --name "v${version}" \
        --yes 2>&1 | tee /tmp/push-output.txt; then
        
        log_success "Successfully pushed $TEMPLATE_NAME (v${version})"
        save_version "$TEMPLATE_NAME" "$version"
        
        # Cleanup
        docker exec coder rm -rf "/tmp/${TEMPLATE_NAME}-push"
        return 0
    else
        log_error "Failed to push template"
        docker exec coder rm -rf "/tmp/${TEMPLATE_NAME}-push"
        return 1
    fi
}

# =============================================================================
# Main Flow
# =============================================================================

main() {
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🚀 Coder Template Push v2"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Load environment
    load_env
    
    # Validate template
    validate_template
    
    # Determine version
    if [[ -z "$VERSION_NAME" ]]; then
        VERSION_NUM=$(get_next_version "$TEMPLATE_NAME")
    else
        VERSION_NUM="${VERSION_NAME#v}"  # Strip 'v' prefix if present
    fi
    
    log_info "Template: $TEMPLATE_NAME"
    log_info "Version:  v$VERSION_NUM"
    log_info "Base Domain: $BASE_DOMAIN"
    log_info "Host IP: $HOST_IP"
    echo ""
    
    # Create temp build directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf '$TEMP_DIR'" EXIT
    
    # Copy template to temp dir
    cp -r "$TEMPLATE_DIR"/* "$TEMP_DIR/"
    
    # Process template
    substitute_variables "$TEMP_DIR"
    compile_startup_script "$TEMP_DIR"
    
    # Dry run - just show what would happen
    if $DRY_RUN; then
        log_warn "DRY RUN - Not pushing to Coder"
        echo ""
        log_info "Files that would be pushed:"
        find "$TEMP_DIR" -type f | sort | while read -r f; do
            echo "  ${f#$TEMP_DIR/}"
        done
        echo ""
        log_info "Variables.tf contents:"
        if [[ -f "$TEMP_DIR/variables.tf" ]]; then
            cat "$TEMP_DIR/variables.tf"
        else
            echo "  (no variables.tf)"
        fi
        echo ""
        log_success "Dry run complete"
        exit 0
    fi
    
    # Push to Coder
    push_to_coder "$TEMP_DIR" "$VERSION_NUM"
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "🎉 Complete! Template: $TEMPLATE_NAME (v$VERSION_NUM)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
