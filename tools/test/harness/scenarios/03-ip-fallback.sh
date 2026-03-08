#!/bin/bash
# harness/scenarios/03-ip-fallback.sh
# Scenario: No domain config at all — IP-only access.
# No Cloudflare token required.
#
# Asserts: DOMAIN_MODE=ip, traefik running on IP, no cloudflare-tunnel, no pihole.

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="03-ip-fallback"

source "$HARNESS_DIR/lib/assertions.sh"
source "$HARNESS_DIR/lib/snapshot.sh"
source "$HARNESS_DIR/lib/teardown.sh"

echo "============================================================"
echo " Scenario $SCENARIO_NAME"
echo "============================================================"
echo ""

export STACK_DIR

save_stack_state "$SCENARIO_NAME"
register_teardown

echo "[SCENARIO] Running interactive setup (IP fallback — no domain)..."
if ! expect "$HARNESS_DIR/expect/setup-ip-interactive.exp"; then
    echo "[SCENARIO ERROR] expect script failed"
    exit 1
fi

# Start the stack (core only — no networking, no tunnel)
echo "[SCENARIO] Starting stack..."
pushd "$STACK_DIR" >/dev/null
docker compose --profile core up -d 2>&1 | tail -5
sleep 10
popd >/dev/null

# Assertions
echo ""
echo "[SCENARIO] Running assertions..."

assert_env_var "$STACK_DIR/.env" "DOMAIN_MODE" "ip"
assert_env_var "$STACK_DIR/.env" "BASE_DOMAIN" "localhost"

# Verify no networking-profile containers are running
assert_container_stopped "cloudflare-tunnel"
assert_container_stopped "pihole"
assert_container_stopped "traefik"

# Glance dashboard should be accessible on port 8080 (core profile)
HOST_IP_VAL=$(grep "^HOST_IP=" "$STACK_DIR/.env" | cut -d'=' -f2 | tr -d ' "')
assert_url_responds "http://${HOST_IP_VAL}:8080" "200" 15

echo ""
if print_assertion_summary; then
    echo "[SCENARIO] $SCENARIO_NAME PASSED"
    exit 0
else
    echo "[SCENARIO] $SCENARIO_NAME FAILED"
    exit 1
fi
