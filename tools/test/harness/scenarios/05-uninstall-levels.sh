#!/bin/bash
# harness/scenarios/05-uninstall-levels.sh
# Scenario: Tests all three uninstall levels sequentially.
# Requires a working baseline stack (spin one up with IP fallback first).
#
# Flow:
#   Setup (quick) → assert running → Uninstall L1 → assert containers gone, data present
#   Re-setup      → Uninstall L2 → assert data/ cleaned
#   Re-setup      → Uninstall L3 → assert images removed (spot-check)

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="05-uninstall-levels"

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

# ────────────────────────────────────────────────────────────────────
# Helper: do a quick (non-interactive) setup and start the stack
# ────────────────────────────────────────────────────────────────────
quick_setup_and_start() {
    echo "[SCENARIO] Running quick setup..."
    pushd "$STACK_DIR" >/dev/null
    ./setup.sh --quick --skip-pull --skip-cloudflare --skip-certs 2>&1 | tail -10
    docker compose --profile core up -d 2>&1 | tail -5
    sleep 8
    popd >/dev/null
}

# ────────────────────────────────────────────────────────────────────
# Level 1: containers and volumes removed, data/ preserved
# ────────────────────────────────────────────────────────────────────
quick_setup_and_start

reset_assertion_counts
echo ""
echo "[SCENARIO] Running Level 1 uninstall..."
export HARNESS_UNINSTALL_LEVEL=1
expect "$HARNESS_DIR/expect/uninstall.exp" 2>&1 | tail -5
sleep 3

echo "[SCENARIO] Level 1 assertions..."
assert_container_stopped "traefik"
assert_container_stopped "glance"

# data/ should still exist at L1
if [[ -d "$STACK_DIR/data" ]]; then
    _assert_pass "data/ directory preserved after Level 1 uninstall"
else
    _assert_fail "data/ directory preserved after Level 1 uninstall"
fi

print_assertion_summary
L1_RESULT=$?

# ────────────────────────────────────────────────────────────────────
# Level 2: data/, files/, config/ removed
# ────────────────────────────────────────────────────────────────────
quick_setup_and_start

reset_assertion_counts
echo ""
echo "[SCENARIO] Running Level 2 uninstall..."
export HARNESS_UNINSTALL_LEVEL=2
expect "$HARNESS_DIR/expect/uninstall.exp" 2>&1 | tail -5
sleep 3

echo "[SCENARIO] Level 2 assertions..."
assert_container_stopped "traefik"
assert_dir_absent "$STACK_DIR/data"
assert_dir_absent "$STACK_DIR/files"

print_assertion_summary
L2_RESULT=$?

# ────────────────────────────────────────────────────────────────────
# Level 3: Docker images removed (spot-check core image)
# ────────────────────────────────────────────────────────────────────
quick_setup_and_start

reset_assertion_counts
echo ""
echo "[SCENARIO] Running Level 3 uninstall..."
export HARNESS_UNINSTALL_LEVEL=3
expect "$HARNESS_DIR/expect/uninstall.exp" 2>&1 | tail -5
sleep 5

echo "[SCENARIO] Level 3 assertions..."
assert_container_stopped "traefik"
assert_dir_absent "$STACK_DIR/data"

# Check that at least one core image is gone
TRAEFIK_IMAGE="traefik"
if ! docker images --format '{{.Repository}}' | grep -q "^${TRAEFIK_IMAGE}$"; then
    _assert_pass "traefik image removed after Level 3 uninstall"
else
    _assert_fail "traefik image removed after Level 3 uninstall" "image still present"
fi

print_assertion_summary
L3_RESULT=$?

# ────────────────────────────────────────────────────────────────────
echo ""
if [[ $L1_RESULT -eq 0 && $L2_RESULT -eq 0 && $L3_RESULT -eq 0 ]]; then
    echo "[SCENARIO] $SCENARIO_NAME PASSED"
    exit 0
else
    echo "[SCENARIO] $SCENARIO_NAME FAILED (L1=$L1_RESULT L2=$L2_RESULT L3=$L3_RESULT)"
    exit 1
fi
