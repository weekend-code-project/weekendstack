#!/bin/bash
# harness/lib/secrets.sh
# Loads and validates test secrets from ~/.weekendstack/test-secrets
# Never logs the full token — only the first 4 characters.

SECRETS_FILE="${HOME}/.weekendstack/test-secrets"

load_secrets() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        echo "[HARNESS ERROR] Secrets file not found: $SECRETS_FILE" >&2
        echo "[HARNESS INFO]  Run 'make test-secrets-setup' to create a template." >&2
        return 1
    fi

    local perms
    perms=$(stat -c "%a" "$SECRETS_FILE" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        echo "[HARNESS WARN] Secrets file permissions are $perms (expected 600)." >&2
        echo "[HARNESS WARN] Fixing automatically..." >&2
        chmod 600 "$SECRETS_FILE"
    fi

    # Source the file — it should contain KEY=value pairs
    # shellcheck source=/dev/null
    set -a
    source "$SECRETS_FILE"
    set +a

    local missing=()
    [[ -z "${CF_API_TOKEN:-}" ]]   && missing+=("CF_API_TOKEN")
    [[ -z "${CF_ZONE_DOMAIN:-}" ]] && missing+=("CF_ZONE_DOMAIN")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[HARNESS ERROR] Missing required secrets: ${missing[*]}" >&2
        echo "[HARNESS INFO]  Edit $SECRETS_FILE and add the missing variables." >&2
        return 1
    fi

    # Mask token in all future output by exporting a censored version for logs
    export CF_API_TOKEN_MASKED="${CF_API_TOKEN:0:4}****"
    export CF_API_TOKEN
    export CF_ZONE_DOMAIN
    # Optional: pre-supplied account ID speeds up first API call
    export CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"

    echo "[HARNESS] Secrets loaded (token: ${CF_API_TOKEN_MASKED}, domain: ${CF_ZONE_DOMAIN})"
    return 0
}

create_secrets_template() {
    local dir
    dir=$(dirname "$SECRETS_FILE")
    mkdir -p "$dir"

    if [[ -f "$SECRETS_FILE" ]]; then
        echo "[HARNESS] Secrets file already exists: $SECRETS_FILE"
        return 0
    fi

    cat > "$SECRETS_FILE" << 'EOF'
# ~/.weekendstack/test-secrets
# Cloudflare credentials used by the WeekendStack test harness.
# Keep this file chmod 600. Never commit it to version control.

# Cloudflare API token with:
#   - Account > Cloudflare Tunnel > Edit
#   - Zone > DNS > Edit  (for CF_ZONE_DOMAIN)
# Create at: https://dash.cloudflare.com/profile/api-tokens
CF_API_TOKEN=

# Domain managed in your Cloudflare account (used for test tunnels)
CF_ZONE_DOMAIN=

# (Optional) Cloudflare Account ID — auto-detected if empty
CF_ACCOUNT_ID=
EOF

    chmod 600 "$SECRETS_FILE"
    echo "[HARNESS] Created secrets template: $SECRETS_FILE"
    echo "[HARNESS] Fill in CF_API_TOKEN and CF_ZONE_DOMAIN, then re-run the harness."
}
