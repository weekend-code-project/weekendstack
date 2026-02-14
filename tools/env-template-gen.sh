#!/bin/bash
# Auto-generate .env file from .env.example with secure random values
# This script finds all <GENERATE> tags and replaces them with appropriate random values

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_EXAMPLE="${PROJECT_ROOT}/.env.example"
ENV_FILE="${PROJECT_ROOT}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_info() { echo -e "${YELLOW}→${NC} $1"; }

# Check if .env.example exists
if [[ ! -f "$ENV_EXAMPLE" ]]; then
    log_error ".env.example not found at $ENV_EXAMPLE"
    exit 1
fi

# Copy .env.example to .env
log_info "Generating .env from template..."
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

log_success ".env file generated successfully"
log_info "All secrets and keys have been auto-generated"
log_info "Review and customize settings in .env before deploying"

exit 0
