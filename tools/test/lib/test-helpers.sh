#!/bin/bash
# =============================================================================
# Shared Test Helpers for Coder Template Tests
# =============================================================================
# Source this file from individual template test scripts.
# Provides: colors, logging, assert helpers, coder helpers, preflight,
#           workspace creation, status checks, cleanup, and summary.
#
# Expected variables (set before sourcing):
#   TEMPLATE_NAME        - Name of the template to test
#   CREATE_PARAMS        - Array of --parameter flags for workspace creation
#   WAIT_AGENT_TIMEOUT   - (optional, default 120s)
#   WAIT_SCRIPTS_TIMEOUT - (optional, default 180s)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ─── Defaults ────────────────────────────────────────────────
WORKSPACE_NAME="ci-test-$(date +%s)"
KEEP_WORKSPACE=false
CODER_CONTAINER="coder"
WAIT_AGENT_TIMEOUT="${WAIT_AGENT_TIMEOUT:-120}"
WAIT_SCRIPTS_TIMEOUT="${WAIT_SCRIPTS_TIMEOUT:-180}"

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --keep) KEEP_WORKSPACE=true ;;
    esac
done

# ─── Colors & Output ────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILURES=()

log()      { echo -e "${BLUE}[TEST]${NC} $1"; }
log_pass() { echo -e "  ${GREEN}✓${NC} $1"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_PASSED=$((TESTS_PASSED+1)); }
log_fail() { echo -e "  ${RED}✗${NC} $1${2:+ — $2}"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); FAILURES+=("$1: ${2:-}"); }
log_skip() { echo -e "  ${YELLOW}○${NC} $1 (skipped: $2)"; TESTS_SKIPPED=$((TESTS_SKIPPED+1)); }
log_section() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

# ─── Helper: Run coder CLI inside Coder container ───────────
coder_exec() {
    docker exec -e CODER_SESSION_TOKEN="$CODER_SESSION_TOKEN" "$CODER_CONTAINER" coder "$@" 2>&1
}

# ─── Helper: Run command inside workspace container ─────────
workspace_exec() {
    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        echo "ERROR: workspace container not found" >&2
        return 1
    fi
    docker exec -u coder "$container" bash -c "$1" 2>&1
}

# ─── Helper: Run command as root inside workspace ───────────
workspace_exec_root() {
    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        echo "ERROR: workspace container not found" >&2
        return 1
    fi
    docker exec "$container" bash -c "$1" 2>&1
}

# ─── Helper: Get workspace container name ───────────────────
get_workspace_container() {
    docker ps --filter "name=coder-jessefreeman-${WORKSPACE_NAME}" --format "{{.Names}}" | head -1
}

# ─── Helper: Check API endpoint ─────────────────────────────
coder_api() {
    curl -sf -H "Coder-Session-Token: $CODER_SESSION_TOKEN" "http://localhost:7080$1" 2>/dev/null
}

# ─── Assert helpers ──────────────────────────────────────────
assert_contains() {
    local haystack="$1" needle="$2" test_name="$3"
    if echo "$haystack" | grep -q "$needle" 2>/dev/null; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "expected to contain '$needle'"
    fi
}

assert_not_empty() {
    local value="$1" test_name="$2"
    if [[ -n "$value" ]]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "value was empty"
    fi
}

assert_equals() {
    local actual="$1" expected="$2" test_name="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "expected '$expected', got '$actual'"
    fi
}

assert_exit_code() {
    local code="$1" expected="$2" test_name="$3"
    if [[ "$code" -eq "$expected" ]]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "expected exit code $expected, got $code"
    fi
}

# ─── Wait for startup scripts to finish ─────────────────────
wait_for_startup() {
    local label="${1:-startup scripts}"
    local check_cmd="${2:-}"
    local timeout="${3:-$WAIT_SCRIPTS_TIMEOUT}"

    log "Waiting for $label to complete (timeout: ${timeout}s)..."
    local start_time=$SECONDS
    while [[ $((SECONDS - start_time)) -lt $timeout ]]; do
        if [[ -n "$check_cmd" ]]; then
            if workspace_exec "$check_cmd" &>/dev/null; then
                local elapsed=$((SECONDS - start_time))
                log_pass "$label completed (${elapsed}s)"
                return 0
            fi
        fi
        sleep 5
    done
    log_fail "$label completed" "timed out after ${timeout}s"
    return 1
}

# ─── Cleanup ─────────────────────────────────────────────────
cleanup() {
    if $KEEP_WORKSPACE; then
        log "Keeping workspace: $WORKSPACE_NAME (--keep flag set)"
        return
    fi
    log "Cleaning up workspace: $WORKSPACE_NAME"
    coder_exec delete "$WORKSPACE_NAME" --yes >/dev/null 2>&1 || true
}

# ─── Preflight ───────────────────────────────────────────────
preflight() {
    log_section "Pre-flight Checks"

    if [[ -z "${CODER_SESSION_TOKEN:-}" ]]; then
        echo -e "${RED}ERROR: CODER_SESSION_TOKEN not set${NC}"
        echo "  export CODER_SESSION_TOKEN=<your-token>"
        exit 1
    fi
    log_pass "CODER_SESSION_TOKEN is set"

    local coder_status
    coder_status=$(docker ps --filter "name=$CODER_CONTAINER" --filter "status=running" --format "{{.Names}}" | head -1)
    if [[ "$coder_status" != "$CODER_CONTAINER" ]]; then
        log_fail "Coder container running" "container '$CODER_CONTAINER' not found"
        exit 1
    fi
    log_pass "Coder container is running"

    local health
    health=$(docker inspect "$CODER_CONTAINER" --format "{{.State.Health.Status}}" 2>/dev/null || echo "unknown")
    if [[ "$health" != "healthy" ]]; then
        log_fail "Coder is healthy" "status: $health"
        exit 1
    fi
    log_pass "Coder is healthy"

    local template_list
    template_list=$(coder_exec templates list --output json 2>/dev/null)
    if ! echo "$template_list" | python3 -c "
import json,sys
data=json.load(sys.stdin)
names=[t.get('Template',t).get('name','') for t in data]
sys.exit(0 if '$TEMPLATE_NAME' in names else 1)
" 2>/dev/null; then
        log_fail "Template exists" "template '$TEMPLATE_NAME' not found"
        exit 1
    fi
    log_pass "Template '$TEMPLATE_NAME' exists"

    local existing
    existing=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
print(any(w.get('name','')=='$WORKSPACE_NAME' for w in data))
" 2>/dev/null || echo "false")
    if [[ "$existing" == "True" || "$existing" == "true" ]]; then
        log "Deleting existing workspace: $WORKSPACE_NAME"
        coder_exec delete "$WORKSPACE_NAME" --yes >/dev/null 2>&1
    fi
    log_pass "No conflicting workspace"
}

# ─── Create workspace ───────────────────────────────────────
create_workspace() {
    log_section "Workspace Creation"
    log "Creating workspace: $WORKSPACE_NAME (template: $TEMPLATE_NAME)"

    local create_output
    create_output=$(coder_exec create "$WORKSPACE_NAME" \
        --template "$TEMPLATE_NAME" \
        "${CREATE_PARAMS[@]}" \
        --yes 2>&1)
    local create_exit=$?

    if [[ $create_exit -eq 0 ]]; then
        log_pass "Workspace created successfully"
    else
        log_fail "Workspace created" "exit code: $create_exit"
        echo "$create_output" | tail -15
        return 1
    fi

    if echo "$create_output" | grep -qi "error.*creation errored\|error.*bind source"; then
        log_fail "No creation errors" "found error in build output"
    else
        log_pass "No creation errors in build output"
    fi
}

# ─── Wait for workspace to be running ───────────────────────
wait_for_workspace() {
    log_section "Workspace Status"
    log "Waiting for agent to connect (timeout: ${WAIT_AGENT_TIMEOUT}s)..."

    local start_time=$SECONDS
    local status=""
    while [[ $((SECONDS - start_time)) -lt $WAIT_AGENT_TIMEOUT ]]; do
        status=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data:
    if w.get('name','') == '$WORKSPACE_NAME':
        print(w.get('latest_build',{}).get('status',''))
        break
" 2>/dev/null || echo "unknown")
        if [[ "$status" == "running" || "$status" == "started" ]]; then
            break
        fi
        sleep 2
    done

    local elapsed=$((SECONDS - start_time))
    if [[ "$status" == "running" || "$status" == "started" ]]; then
        log_pass "Workspace started (${elapsed}s)"
    else
        log_fail "Workspace started" "status: '$status' after ${elapsed}s"
        return 1
    fi
}

# ─── Test container basics ──────────────────────────────────
test_container_basics() {
    log_section "Container Basics"

    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_fail "Workspace container exists" "no container found"
        return 1
    fi
    log_pass "Workspace container exists ($container)"

    local state
    state=$(docker inspect "$container" --format "{{.State.Status}}" 2>/dev/null)
    assert_equals "$state" "running" "Container is running"

    local networks
    networks=$(docker inspect "$container" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
    assert_contains "$networks" "coder-network" "Container on coder-network"

    local mounts
    mounts=$(docker inspect "$container" --format '{{range .Mounts}}{{.Destination}} {{end}}' 2>/dev/null)
    assert_contains "$mounts" "/home/coder" "Home directory mounted"
}

# ─── Test code-server ───────────────────────────────────────
test_code_server() {
    log_section "Code Server"

    local cs_pid
    cs_pid=$(workspace_exec_root "pgrep -f 'code-server' | head -1" || echo "")
    if [[ -n "$cs_pid" ]]; then
        log_pass "code-server process running"
    else
        log "Waiting for code-server to start..."
        sleep 15
        cs_pid=$(workspace_exec_root "pgrep -f 'code-server' | head -1" || echo "")
        if [[ -n "$cs_pid" ]]; then
            log_pass "code-server process running (delayed start)"
        else
            log_fail "code-server process running" "not found"
        fi
    fi
}

# ─── Print test summary ─────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Test Results — ${TEMPLATE_NAME}${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "  Total:   $TESTS_RUN"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"

    if [[ ${#FAILURES[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${RED}Failures:${NC}"
        for f in "${FAILURES[@]}"; do
            echo -e "    ${RED}✗${NC} $f"
        done
    fi

    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "  ${RED}$TESTS_FAILED test(s) failed${NC}"
        exit 1
    fi
}
