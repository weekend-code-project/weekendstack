#!/bin/bash
# Auto-generate .env file from template with secure random values
# This script finds all <GENERATE> tags and replaces them with appropriate random values
#
# Usage:
#   ./tools/env-template-gen.sh <template_file> [output_file]
#
# Examples:
#   ./tools/env-template-gen.sh .env.tmp                 # Use .env.tmp -> .env
#   ./tools/env-template-gen.sh custom.template .env.new # Custom template and output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default to the assembled temp template when present. If no temp template
# is provided, always assemble a fresh full one so the documented no-arg flow
# is deterministic and does not depend on leftover test or setup state.
if [[ -n "${1:-}" ]]; then
    ENV_EXAMPLE="$1"
else
    "${PROJECT_ROOT}/tools/env/scripts/assemble-env.sh" \
        --profiles "all" \
        --output "${PROJECT_ROOT}/.env.tmp" >/dev/null 2>&1

    if [[ -f "${PROJECT_ROOT}/.env.tmp" ]]; then
        ENV_EXAMPLE="${PROJECT_ROOT}/.env.tmp"
    else
        ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"
    fi
fi

ENV_FILE="${2:-${PROJECT_ROOT}/.env}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_info() { echo -e "${YELLOW}→${NC} $1"; }

# Check if template exists
if [[ ! -f "$ENV_EXAMPLE" ]]; then
    echo "Error: Template file not found: $ENV_EXAMPLE"
    exit 1
fi

# Show which template we're using
template_name=$(basename "$ENV_EXAMPLE")
log_info "Generating .env from template: $template_name"
cp "$ENV_EXAMPLE" "$ENV_FILE"

# Function to generate random value based on comment
generate_value() {
    local comment="$1"
    
    if [[ "$comment" =~ "openssl rand -hex 64" ]]; then
        openssl rand -hex 64
    elif [[ "$comment" =~ "openssl rand -hex 32" ]]; then
        openssl rand -hex 32
    elif [[ "$comment" =~ "openssl rand -hex 16" ]]; then
        openssl rand -hex 16
    elif [[ "$comment" =~ "openssl rand -base64 32" ]]; then
        openssl rand -base64 32
    elif [[ "$comment" =~ "openssl rand -base64 24" ]]; then
        openssl rand -base64 24
    elif [[ "$comment" =~ "openssl rand -base64" ]]; then
        openssl rand -base64 32
    else
        # Default to hex 32
        openssl rand -hex 32
    fi
}

# Process each line with <GENERATE> tag
while IFS= read -r line; do
    # Skip if not a variable assignment line with <GENERATE> (allow letters, numbers, underscores)
    if [[ ! "$line" =~ ^[A-Z0-9_]+=.*#.*"<GENERATE>" ]]; then
        continue
    fi
    
    # Extract variable name, current value, and generation instruction
    var_name=$(echo "$line" | cut -d'=' -f1)
    comment=$(echo "$line" | grep -oP '#.*$')
    
    # Generate random value
    random_value=$(generate_value "$comment")
    
    # Replace in .env file
    sed -i "s|^${var_name}=.*|${var_name}=${random_value}|" "$ENV_FILE"
    
done < "$ENV_EXAMPLE"

# Set setup metadata
sed -i "s/^SETUP_DATE=.*/SETUP_DATE=$(date +%Y-%m-%d)/" "$ENV_FILE"

# Strip inline comments from variable assignment lines
# Docker Compose does not reliably handle inline comments in .env files
# Pattern: VAR=value  # comment  ->  VAR=value
# Preserves full-line comments (lines starting with #) and values containing #
sed -i -E '/^[A-Za-z_][A-Za-z0-9_]*=/ {
    /^[A-Za-z_][A-Za-z0-9_]*=[^#]*#/ {
        s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]#]*)[[:space:]]+#.*$/\1/
    }
}' "$ENV_FILE"

# Count generated secrets
secret_count=$(grep -c "^[A-Z0-9_]*=.*#.*<GENERATE>" "$ENV_EXAMPLE" || true)
log_success ".env file generated successfully"
log_info "Template: $template_name"
log_info "Generated: $secret_count secrets and keys"
log_info "Output: $ENV_FILE"
echo ""
log_info "Review and customize settings in .env before deploying"

exit 0
