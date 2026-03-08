#!/bin/bash
# harness/lib/teardown.sh
# Teardown helpers: stop the stack, delete test Cloudflare tunnels, restore state.
# Each scenario registers a trap that calls full_teardown.

STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"

# delete_test_tunnel ACCOUNT_ID TUNNEL_ID [API_TOKEN]
# Deletes a Cloudflare tunnel by ID via the API.
delete_test_tunnel() {
    local account_id="$1" tunnel_id="$2"
    local token="${3:-${CF_API_TOKEN:-}}"

    if [[ -z "$token" || -z "$account_id" || -z "$tunnel_id" ]]; then
        echo "[TEARDOWN] Skipping tunnel delete — missing account_id/tunnel_id/token"
        return 0
    fi

    echo "[TEARDOWN] Deleting test tunnel $tunnel_id..."

    # First, clean active connections (required before delete)
    curl -sf --max-time 10 -X DELETE \
        "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel/$tunnel_id/connections" \
        -H "Authorization: Bearer $token" >/dev/null 2>&1 || true

    sleep 2

    local response
    response=$(curl -sf --max-time 15 -X DELETE \
        "https://api.cloudflare.com/client/v4/accounts/$account_id/cfd_tunnel/$tunnel_id" \
        -H "Authorization: Bearer $token" 2>/dev/null)

    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo "[TEARDOWN] Tunnel $tunnel_id deleted"
    else
        echo "[TEARDOWN WARN] Could not delete tunnel $tunnel_id (may already be gone)"
        echo "$response" | jq -r '.errors[]?.message' 2>/dev/null || true
    fi
}

# stop_stack
# Gracefully stops all containers managed by docker compose.
stop_stack() {
    echo "[TEARDOWN] Stopping stack..."
    pushd "$STACK_DIR" >/dev/null
    docker compose down --remove-orphans --timeout 30 2>/dev/null || true
    popd >/dev/null
    echo "[TEARDOWN] Stack stopped"
}

# full_teardown [TUNNEL_ID] [ACCOUNT_ID]
# Called from EXIT traps in scenario scripts.
# 1. Stops the live stack
# 2. Deletes the test Cloudflare tunnel (if provided)
# 3. Restores the pre-test state from snapshot
full_teardown() {
    local tunnel_id="${1:-${_HARNESS_TEST_TUNNEL_ID:-}}"
    local account_id="${2:-${_HARNESS_TEST_ACCOUNT_ID:-}}"

    echo ""
    echo "[TEARDOWN] Starting teardown..."

    stop_stack

    if [[ -n "$tunnel_id" && -n "$account_id" ]]; then
        delete_test_tunnel "$account_id" "$tunnel_id"
    fi

    # Restore pre-test snapshot
    if declare -f restore_stack_state >/dev/null 2>&1; then
        restore_stack_state
    fi

    echo "[TEARDOWN] Done"
}

# register_teardown [TUNNEL_ID] [ACCOUNT_ID]
# Call this early in each scenario to register cleanup on EXIT.
register_teardown() {
    export _HARNESS_TEST_TUNNEL_ID="${1:-}"
    export _HARNESS_TEST_ACCOUNT_ID="${2:-}"
    trap 'full_teardown "$_HARNESS_TEST_TUNNEL_ID" "$_HARNESS_TEST_ACCOUNT_ID"' EXIT
}
