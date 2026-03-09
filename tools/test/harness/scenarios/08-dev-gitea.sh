#!/bin/bash
# harness/scenarios/08-dev-gitea.sh
# Scenario: core + dev profiles, Gitea git service, IP-only access.
# Stack is LEFT RUNNING after test so you can inspect/use it.
#
# Pre-requisites: Docker running, no CF token needed.
#
# Flow:
#  1. Stop current stack + remove Coder & Gitea DB volumes (clean credential init)
#  2. Run interactive setup: core+dev, git=gitea, no Cloudflare, IP access
#  3. Start stack
#  4. Wait for Coder and Gitea to become healthy
#  5. Assert: coder, coder-database, gitea, gitea-database running; API healthy
#  6. Print service URLs — stack stays UP for user to use

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"
SCENARIO_NAME="08-dev-gitea"
HOST_IP="${HARNESS_HOST_IP:-$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)}"

source "$HARNESS_DIR/lib/assertions.sh"

echo "════════════════════════════════════════════════════════════"
echo " Scenario $SCENARIO_NAME"
echo " Test: Coder + Gitea (dev profile) + IP-only access"
echo " Stack will be LEFT RUNNING after test."
echo "════════════════════════════════════════════════════════════"
echo ""

export STACK_DIR HARNESS_HOST_IP="$HOST_IP"

# ── Stop any running stack cleanly ───────────────────────────────────────────
echo "[SCENARIO] Stopping current stack (if running)..."
pushd "$STACK_DIR" >/dev/null
docker compose down --remove-orphans --timeout 30 2>&1 | tail -5 || true
popd >/dev/null

# Remove Coder and Gitea DB volumes so fresh init uses new credentials.
echo "[SCENARIO] Removing DB volumes for clean credential init..."
for vol in weekendstack_coder-db-data weekendstack_gitea-db-data; do
    docker volume rm "$vol" 2>/dev/null && \
        echo "  Removed: $vol" || \
        echo "  (not found: $vol)"
done
echo ""

# ── Run interactive setup via expect ─────────────────────────────────────────
echo "[SCENARIO] Running setup: core + dev + Gitea..."
if ! expect "$HARNESS_DIR/expect/setup-dev-gitea.exp" 2>&1; then
    echo ""
    echo "[SCENARIO ERROR] expect-driven setup failed"
    exit 1
fi
echo ""

# ── Confirm generated .env ────────────────────────────────────────────────────
echo "[SCENARIO] Generated .env values:"
CODER_URL=$(grep "^CODER_ACCESS_URL=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || true)
GITEA_PORT=$(grep "^GITEA_PORT=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || true)
GITEA_PORT="${GITEA_PORT:-3300}"
COMPOSE_PROFS=$(grep "^COMPOSE_PROFILES=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
echo "  CODER_ACCESS_URL = ${CODER_URL:-<not set>}"
echo "  GITEA_PORT       = $GITEA_PORT"
echo "  COMPOSE_PROFILES = ${COMPOSE_PROFS:-<not set>}"
echo ""

# ── Start the stack ───────────────────────────────────────────────────────────
echo "[SCENARIO] Starting stack..."
pushd "$STACK_DIR" >/dev/null
PROFILE_ARGS=""
IFS=',' read -ra _PROFS <<< "${COMPOSE_PROFS:-core,dev}"
for p in "${_PROFS[@]}"; do
    PROFILE_ARGS="$PROFILE_ARGS --profile $p"
done
echo "  docker compose $PROFILE_ARGS up -d"
# shellcheck disable=SC2086
docker compose $PROFILE_ARGS up -d 2>&1
popd >/dev/null
echo ""

# ── Wait for Coder ────────────────────────────────────────────────────────────
CODER_URL="${CODER_URL:-http://${HOST_IP}:7080}"
echo "[SCENARIO] Waiting for Coder at $CODER_URL (up to 300s)..."
elapsed=0
while [[ $elapsed -lt 300 ]]; do
    if curl -sf --max-time 3 "${CODER_URL}/api/v2/buildinfo" >/dev/null 2>&1; then
        echo "[SCENARIO] Coder responded after ${elapsed}s"
        break
    fi
    sleep 5; elapsed=$((elapsed + 5))
    echo "  ${elapsed}s elapsed — waiting..."
done
echo ""

# ── Wait for Gitea ────────────────────────────────────────────────────────────
GITEA_URL="http://${HOST_IP}:${GITEA_PORT}"
echo "[SCENARIO] Waiting for Gitea at $GITEA_URL (up to 120s)..."
elapsed=0
while [[ $elapsed -lt 120 ]]; do
    http_code=$(curl -sf --max-time 3 -o /dev/null -w "%{http_code}" "$GITEA_URL" 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" || "$http_code" == "302" ]]; then
        echo "[SCENARIO] Gitea responded (HTTP $http_code) after ${elapsed}s"
        break
    fi
    sleep 5; elapsed=$((elapsed + 5))
    echo "  ${elapsed}s elapsed (HTTP $http_code) — waiting..."
done
echo ""

# ── Assertions ────────────────────────────────────────────────────────────────
echo "[SCENARIO] Running assertions..."
echo ""

assert_env_var_nonempty "$STACK_DIR/.env" "CODER_ACCESS_URL"
assert_env_var_nonempty "$STACK_DIR/.env" "HOST_IP"

# CODER_ACCESS_URL should be IP-local
_coder_url_val=$(grep "^CODER_ACCESS_URL=" "$STACK_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
if [[ "$_coder_url_val" == *"$HOST_IP"* ]] || [[ "$_coder_url_val" == *"localhost"* ]]; then
    echo "  [PASS] CODER_ACCESS_URL is IP-local: $_coder_url_val"
else
    echo "  [FAIL] CODER_ACCESS_URL should be IP-local, got: $_coder_url_val"
fi

# Container checks
assert_container_running "coder"
assert_container_running "coder-database"
assert_container_running "gitea"
assert_container_running "gitea-database"

# Cloudflare tunnel must NOT be running (no CF configured)
assert_container_stopped "cloudflare-tunnel"

# API health checks
assert_url_responds "${CODER_URL}/api/v2/buildinfo" "200" 10
assert_url_responds "${CODER_URL}/healthz" "200" 10
assert_url_responds "$GITEA_URL" "200" 15

echo ""
if print_assertion_summary; then
    echo "[SCENARIO] ✓ $SCENARIO_NAME PASSED"
else
    echo "[SCENARIO] Some assertions failed — stack is still running for inspection"
fi

echo ""
echo "══════════════════════════════════════════════════════════════"
echo " Stack is RUNNING. Service URLs:"
echo ""
echo "  Coder  → $CODER_URL"
echo "  Gitea  → $GITEA_URL"
echo ""
echo " To stop: docker compose down --remove-orphans"
echo " To restore original config: git checkout .env docker-compose.custom.yml"
echo "══════════════════════════════════════════════════════════════"
