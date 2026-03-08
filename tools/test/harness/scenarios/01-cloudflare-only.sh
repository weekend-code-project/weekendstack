#!/bin/bash
# harness/scenarios/01-cloudflare-only.sh
# Scenario: External domain via Cloudflare Tunnel only. No local domain.
#
# Pre-requisites:
#   - ~/.weekendstack/test-secrets with CF_API_TOKEN and CF_ZONE_DOMAIN
#   - expect installed (sudo apt-get install -y expect)
#
# What it does:
#   1. Saves current stack state (snapshot)
#   2. Runs interactive setup with external domain + CF API token
#   3. Starts the stack
#   4. Asserts DOMAIN_MODE=cloudflare, CF token non-empty, traefik & cloudflare-tunnel running
#   5. Asserts CF API shows tunnel as active
#   6. Teardown: stop stack, delete test tunnel, restore snapshot

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="01-cloudflare-only"

# shellcheck source=../lib/secrets.sh
source "$HARNESS_DIR/lib/secrets.sh"
# shellcheck source=../lib/assertions.sh
source "$HARNESS_DIR/lib/assertions.sh"
# shellcheck source=../lib/snapshot.sh
source "$HARNESS_DIR/lib/snapshot.sh"
# shellcheck source=../lib/teardown.sh
source "$HARNESS_DIR/lib/teardown.sh"

echo "============================================================"
echo " Scenario $SCENARIO_NAME"
echo "============================================================"
echo ""

# ── Load secrets ──────────────────────────────────────────────────────────────
load_secrets || exit 1

# ── Generate a unique subdomain for this test run so we don't clash ───────────
TS=$(date +%s)
TEST_TUNNEL_NAME="weekendstack-harness-${TS}"
# Use CF_ZONE_DOMAIN as BASE_DOMAIN for this test
export HARNESS_BASE_DOMAIN="${CF_ZONE_DOMAIN}"
export HARNESS_CF_API_TOKEN="${CF_API_TOKEN}"
export STACK_DIR

# ── Snapshot current state before touching anything ────────────────────────────
save_stack_state "$SCENARIO_NAME"

# Register teardown. Tunnel ID will be updated after CF wizard runs.
register_teardown "" "${CF_ACCOUNT_ID:-}"

# ── Run interactive setup via expect ──────────────────────────────────────────
echo ""
echo "[SCENARIO] Running interactive setup (Cloudflare only)..."
if ! expect "$HARNESS_DIR/expect/setup-cf-interactive.exp"; then
    echo "[SCENARIO ERROR] expect script failed"
    exit 1
fi
echo "[SCENARIO] Setup completed"

# ── Read tunnel ID created by the wizard ───────────────────────────────────────
TEST_TUNNEL_ID=$(grep "^CLOUDFLARE_TUNNEL_ID=" "$STACK_DIR/.env" 2>/dev/null \
    | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' "')
TEST_ACCOUNT_ID=$(grep "^CLOUDFLARE_ACCOUNT_ID=" "$STACK_DIR/.env" 2>/dev/null \
    | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' "')

# Update teardown with real tunnel ID now that we know it
export _HARNESS_TEST_TUNNEL_ID="$TEST_TUNNEL_ID"
export _HARNESS_TEST_ACCOUNT_ID="$TEST_ACCOUNT_ID"

# ── Start the stack ───────────────────────────────────────────────────────────
echo ""
echo "[SCENARIO] Starting stack..."
pushd "$STACK_DIR" >/dev/null
COMPOSE_PROFILES_VAL=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
docker compose --profile "${COMPOSE_PROFILES_VAL//,/ --profile }" up -d 2>&1 | tail -5
sleep 10
popd >/dev/null

# ── Assertions ────────────────────────────────────────────────────────────────
echo ""
echo "[SCENARIO] Running assertions..."

# .env checks
assert_env_var "$STACK_DIR/.env" "DOMAIN_MODE" "cloudflare"
assert_env_var "$STACK_DIR/.env" "BASE_DOMAIN" "$HARNESS_BASE_DOMAIN"
assert_env_var_nonempty "$STACK_DIR/.env" "CLOUDFLARE_TUNNEL_TOKEN"
assert_env_var_nonempty "$STACK_DIR/.env" "CLOUDFLARE_TUNNEL_ID"

# Container checks
assert_container_running "traefik"
assert_container_running "cloudflare-tunnel"
assert_container_stopped "pihole"

# HTTP check — traefik dashboard (via IP, not domain)
HOST_IP_VAL=$(grep "^HOST_IP=" "$STACK_DIR/.env" | cut -d'=' -f2 | tr -d ' "')
assert_url_responds "http://${HOST_IP_VAL}:8081/dashboard/" "200" 15

# Cloudflare API — tunnel should exist (healthy takes a few seconds)
if [[ -n "$TEST_TUNNEL_ID" && -n "$TEST_ACCOUNT_ID" ]]; then
    sleep 15  # give tunnel time to connect
    assert_tunnel_active "$CF_API_TOKEN" "$TEST_ACCOUNT_ID" "$TEST_TUNNEL_ID"
fi

# Print result
echo ""
if print_assertion_summary; then
    echo "[SCENARIO] $SCENARIO_NAME PASSED"
    SCENARIO_EXIT=0
else
    echo "[SCENARIO] $SCENARIO_NAME FAILED"
    SCENARIO_EXIT=1
fi

# Teardown is registered via trap — runs automatically on exit
exit $SCENARIO_EXIT
