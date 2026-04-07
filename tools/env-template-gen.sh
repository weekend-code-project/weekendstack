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

# Shared validation helpers
source "$PROJECT_ROOT/tools/setup/lib/common.sh"

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

replace_env_var() {
    local var_name="$1"
    local value="$2"
    local file="$3"
    local tmp_file file_dir
    file_dir="$(cd "$(dirname "$file")" && pwd)"
    tmp_file="$(mktemp_in_dir "$file_dir" "$(basename "$file").envgen")"

    awk -v var="$var_name" -v val="$value" '
        BEGIN { updated = 0 }
        $0 ~ ("^" var "=") {
            print var "=" val
            updated = 1
            next
        }
        { print }
        END {
            if (!updated) {
                print var "=" val
            }
        }
    ' "$file" > "$tmp_file"

    replace_file_safely "$tmp_file" "$file"
}

random_chars() {
    local charset="$1"
    local length="$2"
    LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$length"
}

generate_shared_admin_password() {
    local candidate
    local attempts=0

    while (( attempts < 20 )); do
        candidate="$(
            printf '%s%s%s%s' \
                "$(random_chars 'A-Z' 1)" \
                "$(random_chars 'a-z' 1)" \
                "$(random_chars '0-9' 1)" \
                "$(random_chars 'A-Za-z0-9._@%+=:!-' 21)"
        )"

        if validate_shared_admin_password "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi

        attempts=$((attempts + 1))
    done

    log_error "Failed to generate a valid shared admin password"
    exit 1
}

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
    local var_name="$1"
    local comment="$2"

    if [[ "$comment" =~ "shared-admin-password" ]]; then
        generate_shared_admin_password
    elif [[ "$comment" =~ "openssl rand -hex 64" ]]; then
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
    if [[ ! "$line" =~ ^[A-Z0-9_]+= ]] || [[ "$line" != *"<GENERATE>"* ]]; then
        continue
    fi
    
    # Extract variable name, current value, and generation instruction
    var_name=$(echo "$line" | cut -d'=' -f1)
    comment=$(printf '%s\n' "$line" | sed 's/^[^#]*//')
    
    # Generate random value
    random_value=$(generate_value "$var_name" "$comment")
    
    # Replace in .env file
    replace_env_var "$var_name" "$random_value" "$ENV_FILE"
    
done < "$ENV_EXAMPLE"

# Set setup metadata
replace_env_var "SETUP_DATE" "$(date +%Y-%m-%d)" "$ENV_FILE"

# Strip inline comments from variable assignment lines.
# Docker Compose does not reliably handle inline comments in .env files.
perl -0pi -e 's/^([A-Za-z_][A-Za-z0-9_]*=[^#\n]*?)[ \t]+#.*$/$1/gm' "$ENV_FILE"

# Count generated secrets
secret_count=$(grep -c "^[A-Z0-9_]*=.*#.*<GENERATE>" "$ENV_EXAMPLE" || true)
log_success ".env file generated successfully"
log_info "Template: $template_name"
log_info "Generated: $secret_count secrets and keys"
log_info "Output: $ENV_FILE"
echo ""
log_info "Review and customize settings in .env before deploying"

exit 0
