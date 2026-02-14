#!/bin/bash
# Auto-generate .env file from .env.example with secure random values
# This script finds all <GENERATE> tags and replaces them with appropriate random values
#
# Usage:
#   ./tools/env-template-gen.sh [input_file] [output_file]
#
# Examples:
#   ./tools/env-template-gen.sh                          # Use .env.example -> .env
#   ./tools/env-template-gen.sh custom.env.example       # Use custom template
#   ./tools/env-template-gen.sh .env.example .env.new    # Custom output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default to .env.example as template
DEFAULT_TEMPLATE="${PROJECT_ROOT}/.env.example"

ENV_EXAMPLE="${1:-$DEFAULT_TEMPLATE}"
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
    log_error "Template file not found at $ENV_EXAMPLE"
    log_info "Expected: .env.example"
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

# Count generated secrets
secret_count=$(grep -c "^[A-Z0-9_]*=.*#.*<GENERATE>" "$ENV_EXAMPLE" || true)
log_success ".env file generated successfully"
log_info "Template: $template_name"
log_info "Generated: $secret_count secrets and keys"
log_info "Output: $ENV_FILE"
echo ""
log_info "Review and customize settings in .env before deploying"

exit 0
