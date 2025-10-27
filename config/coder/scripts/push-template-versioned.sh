#!/bin/bash
# =============================================================================
# SIMPLE VERSIONED TEMPLATE PUSH
# =============================================================================
# Pushes a template with incremental version naming (v1, v2, v3...)
#
# Usage:
#   ./push-template-versioned.sh <template-name>
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

# Configuration
TEMPLATE_NAME="${1:-}"
TEMPLATES_DIR="$(dirname "$0")/../templates"
VERSION_FILE="$(dirname "$0")/.template_versions.json"

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

# Get version
VERSION_NUM=$(get_next_version "$TEMPLATE_NAME")
VERSION_NAME="v${VERSION_NUM}"

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "📤 Pushing Template: $TEMPLATE_NAME"
log "🔢 Version: $VERSION_NAME"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy template to temp directory
TEMP_DIR="/tmp/coder-push-$$"
mkdir -p "$TEMP_DIR"
cp -r "$TEMPLATE_DIR" "$TEMP_DIR/$TEMPLATE_NAME"

# Push using docker exec
log "Copying template to Coder container..."
docker cp "$TEMP_DIR/$TEMPLATE_NAME" coder:/tmp/

log "Pushing template..."
if docker exec coder coder templates push "$TEMPLATE_NAME" \
    --directory "/tmp/$TEMPLATE_NAME" \
    --name "$VERSION_NAME" \
    --yes; then
    
    log "✅ Successfully pushed $TEMPLATE_NAME ($VERSION_NAME)"
    save_version "$TEMPLATE_NAME" "$VERSION_NUM"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    docker exec coder rm -rf "/tmp/$TEMPLATE_NAME"
    
    log "🎉 Complete! Template available as: $TEMPLATE_NAME ($VERSION_NAME)"
else
    log_error "❌ Failed to push template"
    rm -rf "$TEMP_DIR"
    exit 1
fi
