#!/bin/bash
# harness/scenarios/06-reinstall.sh
# Scenario: Full Level 2 uninstall followed by reinstall; asserts containers return.
#
# This validates that a fresh re-setup after a clean wipe works end-to-end.

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="06-reinstall"

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

# ── Step 1: Start a baseline stack ────────────────────────────────────────────
echo "[SCENARIO] Starting baseline stack (quick setup)..."
pushd "$STACK_DIR" >/dev/null
./setup.sh --quick --skip-pull --skip-cloudflare --skip-certs 2>&1 | tail -10
docker compose --profile core up -d 2>&1 | tail -5
sleep 8
popd >/dev/null

# Capture which containers are running before uninstall
BEFORE_CONTAINERS=$(docker ps --format '{{.Names}}' | sort)

# ── Step 2: Full Level 2 uninstall ───────────────────────────────────────────
echo ""
echo "[SCENARIO] Running Level 2 uninstall..."
export HARNESS_UNINSTALL_LEVEL=2
expect "$HARNESS_DIR/expect/uninstall.exp" 2>&1 | tail -5
sleep 3

echo "[SCENARIO] Verifying uninstall cleared data files..."
reset_assertion_counts
assert_dir_absent "$STACK_DIR/data"
print_assertion_summary || true

# ── Step 3: Reinstall ─────────────────────────────────────────────────────────
echo ""
echo "[SCENARIO] Running reinstall (quick setup)..."
pushd "$STACK_DIR" >/dev/null
./setup.sh --quick --skip-pull --skip-cloudflare --skip-certs 2>&1 | tail -10
docker compose --profile core up -d 2>&1 | tail -5
sleep 10
popd >/dev/null

# ── Step 4: Assertions ────────────────────────────────────────────────────────
echo ""
echo "[SCENARIO] Assertions after reinstall..."
reset_assertion_counts

AFTER_CONTAINERS=$(docker ps --format '{{.Names}}' | sort)

# All containers that existed before should be back
while IFS= read -r name; do
    if [[ -z "$name" ]]; then continue; fi
    assert_container_running "$name"
done <<< "$BEFORE_CONTAINERS"

# .env should be recreated
assert_file_exists "$STACK_DIR/.env"
assert_env_var_nonempty "$STACK_DIR/.env" "HOST_IP"

echo ""
if print_assertion_summary; then
    echo "[SCENARIO] $SCENARIO_NAME PASSED"
    exit 0
else
    echo "[SCENARIO] $SCENARIO_NAME FAILED"
    exit 1
fi
