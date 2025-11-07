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
SHARED_MODULES_DIR="$(dirname "$0")/../templates/shared-template-modules"

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

# Initialize version file if it doesn't exist
if [[ ! -f "$VERSION_FILE" ]]; then
    echo '{}' > "$VERSION_FILE"
fi

# Get next version number
get_next_version() {
    local template="$1"
    local current_version
    current_version=$(jq -r --arg t "$template" '.[$t] // 0' "$VERSION_FILE")
    echo $((current_version + 1))
}

# Save version number
save_version() {
    local template="$1"
    local version="$2"
    local temp_file="${VERSION_FILE}.tmp"
    jq --arg t "$template" --argjson v "$version" '.[$t] = $v' "$VERSION_FILE" > "$temp_file"
    mv "$temp_file" "$VERSION_FILE"
}

# Determine next available version name by checking both local counter and remote versions
VERSION_NUM=$(get_next_version "$TEMPLATE_NAME")

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

# Overlay shared modules (do not override if file already exists in template)
overlay_shared_modules() {
    local shared_dir="$1"
    local dest_dir="$2"
    if [[ ! -d "$shared_dir" ]]; then
        log_warn "Shared modules dir not found: $shared_dir (skipping overlay)"
        return 0
    fi
    local count=0
    for f in "$shared_dir"/module-*.tf; do
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
    log "📦 Overlay applied: $count shared module file(s) copied"
}

overlay_shared_modules "$SHARED_MODULES_DIR" "$TEMP_DIR/$TEMPLATE_NAME"

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
        sed -E -i "s|(git::https://github.com/weekend-code-project/weekendstack.git//[^?]+\?ref=)[^\"'\s]+|\1${ENC_REF}|g" "$f"
    done
    log "✏️  Updated ref to '$RESOLVED_REF' in ${#files[@]} file(s)."
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
    log "🔍 Dry run preview: showing lines with '?ref=' after substitution"
    grep -Rn --include='*.tf' '\?ref=' "$TEMP_DIR/$TEMPLATE_NAME" || true
    log "✅ Dry run complete. No changes pushed."
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Perform substitution for actual push
substitute_ref_in_temp "$TEMP_DIR/$TEMPLATE_NAME"

# Push using docker exec
log "Copying template to Coder container..."
docker cp "$TEMP_DIR/$TEMPLATE_NAME" coder:/tmp/

log "Pushing template..."
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec coder coder templates push "$TEMPLATE_NAME" \
        --directory "/tmp/$TEMPLATE_NAME" \
        --name "$VERSION_NAME" \
        --yes 2>&1 | tee /tmp/push-output.txt; then
        
        log "✅ Successfully pushed $TEMPLATE_NAME ($VERSION_NAME)"
        save_version "$TEMPLATE_NAME" "$VERSION_NUM"
        
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
