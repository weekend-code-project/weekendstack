#!/bin/bash
# harness/scenarios/02-pihole-only.sh
# Scenario: Local domain via Pi-Hole DNS only. No external Cloudflare domain.
#
# Asserts: DOMAIN_MODE=pihole, pihole container running, cloudflare-tunnel NOT running.

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="02-pihole-only"

source "$HARNESS_DIR/lib/assertions.sh"
source "$HARNESS_DIR/lib/snapshot.sh"
source "$HARNESS_DIR/lib/teardown.sh"

echo "============================================================"
echo " Scenario $SCENARIO_NAME"
echo "============================================================"
echo ""

export HARNESS_LAB_DOMAIN="testlab"
export STACK_DIR

save_stack_state "$SCENARIO_NAME"
register_teardown

echo "[SCENARIO] Running interactive setup (Pi-Hole local domain only)..."
if ! expect "$HARNESS_DIR/expect/setup-pihole-interactive.exp"; then
    echo "[SCENARIO ERROR] expect script failed"
    exit 1
fi

# Start the stack
echo "[SCENARIO] Starting stack..."
pushd "$STACK_DIR" >/dev/null
COMPOSE_PROFILES_VAL=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"')
docker compose --profile "${COMPOSE_PROFILES_VAL//,/ --profile }" up -d 2>&1 | tail -5
sleep 10
popd >/dev/null

# Assertions
echo ""
echo "[SCENARIO] Running assertions..."

assert_env_var "$STACK_DIR/.env" "DOMAIN_MODE" "pihole"
assert_env_var "$STACK_DIR/.env" "LAB_DOMAIN" "$HARNESS_LAB_DOMAIN"
assert_env_var "$STACK_DIR/.env" "BASE_DOMAIN" "localhost"

assert_container_running "traefik"
assert_container_running "pihole"
assert_container_stopped "cloudflare-tunnel"

HOST_IP_VAL=$(grep "^HOST_IP=" "$STACK_DIR/.env" | cut -d'=' -f2 | tr -d ' "')
assert_url_responds "http://${HOST_IP_VAL}:80" "301" 15

echo ""
if print_assertion_summary; then
    echo "[SCENARIO] $SCENARIO_NAME PASSED"
    exit 0
else
    echo "[SCENARIO] $SCENARIO_NAME FAILED"
    exit 1
fi
