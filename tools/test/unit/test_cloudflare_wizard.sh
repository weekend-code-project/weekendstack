#!/bin/bash
# Unit tests for Cloudflare tunnel setup flow

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

SCRIPT_DIR="$TEST_DIR/project"
mkdir -p "$SCRIPT_DIR/tools/setup/lib"

cp "$PROJECT_ROOT/tools/setup/lib/common.sh" "$SCRIPT_DIR/tools/setup/lib/common.sh"
cp "$PROJECT_ROOT/tools/setup/lib/cloudflare-wizard.sh" "$SCRIPT_DIR/tools/setup/lib/cloudflare-wizard.sh"
cat > "$SCRIPT_DIR/tools/setup/lib/cloudflare-api.sh" <<'EOF'
#!/bin/bash

cf_setup_tunnel_automated() {
    echo "tunnel-123|account-456|weekendstack-tunnel|weekendcodeproject.dev"
}
EOF

source "$SCRIPT_DIR/tools/setup/lib/cloudflare-wizard.sh"

test_suite_start "Cloudflare Wizard"

test_case "API setup persists account ID before follow-up Cloudflare steps"
cat > "$SCRIPT_DIR/.env" <<'EOF'
BASE_DOMAIN=weekendcodeproject.dev
CLOUDFLARE_API_TOKEN=
CLOUDFLARE_ACCOUNT_ID=
CLOUDFLARE_TUNNEL_TOKEN=
EOF

export CLOUDFLARE_API_TOKEN="token-123"
_cf_verify_token() { return 0; }
create_tunnel_config() {
    if grep -q '^CLOUDFLARE_ACCOUNT_ID=account-456$' "$SCRIPT_DIR/.env" && [[ "$CLOUDFLARE_ACCOUNT_ID" == "account-456" ]]; then
        return 0
    fi
    return 1
}
update_env_cloudflare() {
    if grep -q '^CLOUDFLARE_ACCOUNT_ID=account-456$' "$SCRIPT_DIR/.env" && [[ "$CLOUDFLARE_ACCOUNT_ID" == "account-456" ]]; then
        echo "CLOUDFLARE_TUNNEL_TOKEN=connector-token" >> "$SCRIPT_DIR/.env"
        return 0
    fi
    return 1
}
display_tunnel_status() { return 0; }
screen_title() { :; }
log_header() { :; }
log_step() { :; }
log_success() { :; }
log_info() { :; }
log_warn() { :; }
log_error() { :; }

if setup_tunnel_with_api >/dev/null 2>&1 && \
   grep -q '^CLOUDFLARE_ACCOUNT_ID=account-456$' "$SCRIPT_DIR/.env" && \
   grep -q '^CLOUDFLARE_TUNNEL_TOKEN=connector-token$' "$SCRIPT_DIR/.env"; then
    test_pass
else
    test_fail "Expected API setup to persist the account ID before configuring the tunnel"
fi

unset -f _cf_verify_token create_tunnel_config update_env_cloudflare \
    display_tunnel_status screen_title log_header log_step log_success log_info log_warn log_error
unset CLOUDFLARE_API_TOKEN
source "$SCRIPT_DIR/tools/setup/lib/common.sh"
source "$SCRIPT_DIR/tools/setup/lib/cloudflare-wizard.sh"

test_case "update_env_cloudflare reuses an existing connector token without account ID"
cat > "$SCRIPT_DIR/.env" <<'EOF'
BASE_DOMAIN=weekendcodeproject.dev
DOMAIN_MODE=both
COMPOSE_PROFILES=all
CLOUDFLARE_TUNNEL_ENABLED=true
CLOUDFLARE_TUNNEL_NAME=weekendstack-tunnel
CLOUDFLARE_TUNNEL_ID=tunnel-123
CLOUDFLARE_TUNNEL_TOKEN=existing-token
EOF

unset CLOUDFLARE_ACCOUNT_ID

if update_env_cloudflare "weekendstack-tunnel" "tunnel-123" "weekendcodeproject.dev" >/dev/null 2>&1 && \
   grep -q '^CLOUDFLARE_TUNNEL_TOKEN=existing-token$' "$SCRIPT_DIR/.env" && \
   grep -q '^COMPOSE_PROFILES=all,external$' "$SCRIPT_DIR/.env" && \
   grep -q '^DOMAIN_MODE=both$' "$SCRIPT_DIR/.env"; then
    test_pass
else
    test_fail "Expected existing connector token to be preserved and external profile to be enabled"
fi

test_suite_end
