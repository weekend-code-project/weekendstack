#!/bin/bash
# harness/scenarios/07-dev-no-git.sh
# Scenario: core + dev profiles, no git service, IP-only access.
# Tests that Coder starts correctly without Gitea/GitLab.
#
# Pre-requisites: Docker running, no CF token needed.
#
# Flow:
#  1. Snapshot current state
#  2. Stop current stack (uninstall L1)
#  3. Run interactive setup: core+dev, git=none, no Cloudflare, IP access
#  4. Start stack
#  5. Wait for Coder to be healthy (up to 3 min)
#  6. Assert: coder running, coder-database running, gitea NOT running, /api/v2/buildinfo responds
#  7. Teardown: stop stack, restore snapshot

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="07-dev-no-git"
HOST_IP="${HARNESS_HOST_IP:-$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)}"

source "$HARNESS_DIR/lib/assertions.sh"
source "$HARNESS_DIR/lib/snapshot.sh"
source "$HARNESS_DIR/lib/teardown.sh"

echo "════════════════════════════════════════════════════════════"
echo " Scenario $SCENARIO_NAME"
echo " Test: Coder (dev profile) + no git service + IP-only access"
echo "════════════════════════════════════════════════════════════"
echo ""

export STACK_DIR HARNESS_HOST_IP="$HOST_IP"

# ── Snapshot current state ────────────────────────────────────────────────────
save_stack_state "$SCENARIO_NAME"
register_teardown  # stop stack + restore on EXIT

# ── Stop any running stack cleanly ───────────────────────────────────────────
echo "[SCENARIO] Stopping current stack (if running)..."
pushd "$STACK_DIR" >/dev/null
docker compose down --remove-orphans --timeout 30 2>&1 | tail -3 || true
popd >/dev/null

# Remove Coder DB volume so fresh init uses new credentials.
# WARNING: This deletes any existing Coder workspaces/templates in the DB.
echo "[SCENARIO] Removing Coder DB volume for clean credential init..."
docker volume rm weekendstack_coder-db-data 2>/dev/null && \
    echo "  Removed: weekendstack_coder-db-data" || \
    echo "  (volume not found or already removed)"
echo ""

# ── Run interactive setup via expect ─────────────────────────────────────────
echo "[SCENARIO] Running setup: core + dev profiles, no git service..."
if ! expect "$HARNESS_DIR/expect/setup-dev-no-git.exp" 2>&1; then
    echo ""
    echo "[SCENARIO ERROR] expect-driven setup failed"
    exit 1
fi
echo ""

# ── Verify .env looks right before starting ───────────────────────────────────
echo "[SCENARIO] Checking generated .env..."
CODER_URL=$(grep "^CODER_ACCESS_URL=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || true)
GIT_SERVICE=$(grep "^GIT_SERVICE=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || true)
COMPOSE_PROFS=$(grep "^COMPOSE_PROFILES=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
echo "  CODER_ACCESS_URL = ${CODER_URL:-<not set>}"
echo "  GIT_SERVICE      = ${GIT_SERVICE:-<not set>}"
echo "  COMPOSE_PROFILES = ${COMPOSE_PROFS:-<not set>}"
echo ""

# ── Start the stack ───────────────────────────────────────────────────────────
echo "[SCENARIO] Starting stack..."
pushd "$STACK_DIR" >/dev/null
COMPOSE_PROFILES_VAL=$(grep "^COMPOSE_PROFILES=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
if [[ -z "$COMPOSE_PROFILES_VAL" ]]; then
    COMPOSE_PROFILES_VAL=$(grep "^SELECTED_PROFILES=" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
fi
# Build --profile args
PROFILE_ARGS=""
IFS=',' read -ra _PROFS <<< "$COMPOSE_PROFILES_VAL"
for p in "${_PROFS[@]}"; do
    PROFILE_ARGS="$PROFILE_ARGS --profile $p"
done

echo "  docker compose $PROFILE_ARGS up -d"
# shellcheck disable=SC2086
docker compose $PROFILE_ARGS up -d 2>&1
popd >/dev/null
echo ""

# ── Wait for Coder to become healthy ──────────────────────────────────────────
CODER_URL="${CODER_URL:-http://${HOST_IP}:7080}"
echo "[SCENARIO] Waiting for Coder at $CODER_URL (up to 300s)..."
elapsed=0
interval=5
while [[ $elapsed -lt 300 ]]; do
    if curl -sf --max-time 3 "${CODER_URL}/api/v2/buildinfo" >/dev/null 2>&1; then
        echo "[SCENARIO] Coder responded after ${elapsed}s"
        break
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    echo "  ${elapsed}s elapsed — waiting..."
done
echo ""

# ── Assertions ────────────────────────────────────────────────────────────────
echo "[SCENARIO] Running assertions..."
echo ""

# .env assertions — check IP-only access (no external domain)
assert_env_var_nonempty "$STACK_DIR/.env" "CODER_ACCESS_URL"
assert_env_var_nonempty "$STACK_DIR/.env" "HOST_IP"
# CODER_ACCESS_URL should point to local IP, not an external domain
_coder_url_val=$(grep "^CODER_ACCESS_URL=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
if [[ "$_coder_url_val" == *"http://${HOST_IP}"* ]] || [[ "$_coder_url_val" == *"localhost"* ]]; then
    echo "  [PASS] CODER_ACCESS_URL is IP-local: $_coder_url_val"
else
    echo "  [FAIL] CODER_ACCESS_URL should be IP-local, got: $_coder_url_val"
fi

# Container assertions — Coder stack should be up
assert_container_running "coder"
assert_container_running "coder-database"

# Git containers must NOT be running
assert_container_stopped "gitea"
assert_container_stopped "gitlab"

# Coder API must respond
assert_url_responds "${CODER_URL}/api/v2/buildinfo" "200" 10

# Coder health endpoint
assert_url_responds "${CODER_URL}/healthz" "200" 10

echo ""
if print_assertion_summary; then
    echo "[SCENARIO] ✓ $SCENARIO_NAME PASSED"
    echo ""
    echo "  Coder is running at: $CODER_URL"
    echo "  No git service was installed."
    echo "  To deploy templates: make coder-templates"
    exit 0
else
    echo "[SCENARIO] ✗ $SCENARIO_NAME FAILED"
    echo ""
    echo "  Container status:"
    docker ps --format "  {{.Names}}\t{{.Status}}" 2>/dev/null || true
    exit 1
fi
