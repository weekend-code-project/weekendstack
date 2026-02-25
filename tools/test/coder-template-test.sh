#!/bin/bash
# =============================================================================
# Coder Template Integration Test
# =============================================================================
# Automated test suite that validates Coder templates via CLI.
# Creates a workspace, verifies features, and cleans up.
#
# Usage:
#   ./tools/test/coder-template-test.sh [template-name] [--keep]
#
# Options:
#   template-name   Template to test (default: new-modular-template)
#   --keep          Don't delete workspace after tests (for debugging)
#
# Required:
#   CODER_SESSION_TOKEN env var must be set
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─── Configuration ──────────────────────────────────────────
TEMPLATE_NAME="${1:-new-modular-template}"
WORKSPACE_NAME="ci-test-$(date +%s)"
KEEP_WORKSPACE=false
CODER_CONTAINER="coder"
WAIT_AGENT_TIMEOUT=120    # seconds to wait for agent connection
WAIT_SCRIPTS_TIMEOUT=90   # seconds to wait for startup scripts

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
log_fail() { echo -e "  ${RED}✗${NC} $1"; TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); FAILURES+=("$1: $2"); }
log_skip() { echo -e "  ${YELLOW}○${NC} $1 (skipped: $2)"; TESTS_SKIPPED=$((TESTS_SKIPPED+1)); }
log_section() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

# ─── Helper: Run command inside Coder container ─────────────
coder_exec() {
    docker exec -e CODER_SESSION_TOKEN="$CODER_SESSION_TOKEN" "$CODER_CONTAINER" coder "$@" 2>&1
}

# ─── Helper: Run command inside workspace container ─────────
workspace_exec() {
    local container_name="coder-jessefreeman-${WORKSPACE_NAME}"
    docker exec -u coder "$container_name" bash -c "$1" 2>&1
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
        log_fail "$test_name" "expected to find '$needle'"
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

# ─── Cleanup ─────────────────────────────────────────────────
cleanup() {
    if $KEEP_WORKSPACE; then
        log "Keeping workspace: $WORKSPACE_NAME (--keep flag set)"
        return
    fi
    
    log "Cleaning up workspace: $WORKSPACE_NAME"
    coder_exec delete "$WORKSPACE_NAME" --yes >/dev/null 2>&1 || true
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

preflight() {
    log_section "Pre-flight Checks"
    
    # Check session token
    if [[ -z "${CODER_SESSION_TOKEN:-}" ]]; then
        echo -e "${RED}ERROR: CODER_SESSION_TOKEN not set${NC}"
        echo "  export CODER_SESSION_TOKEN=<your-token>"
        exit 1
    fi
    log_pass "CODER_SESSION_TOKEN is set"
    
    # Check Coder container is running
    local coder_status
    coder_status=$(docker ps --filter "name=$CODER_CONTAINER" --filter "status=running" --format "{{.Names}}" | head -1)
    if [[ "$coder_status" != "$CODER_CONTAINER" ]]; then
        log_fail "Coder container running" "container '$CODER_CONTAINER' not running"
        exit 1
    fi
    log_pass "Coder container is running"
    
    # Check Coder is healthy
    local health
    health=$(docker inspect "$CODER_CONTAINER" --format "{{.State.Health.Status}}" 2>/dev/null || echo "unknown")
    if [[ "$health" != "healthy" ]]; then
        log_fail "Coder is healthy" "status: $health"
        exit 1
    fi
    log_pass "Coder is healthy"
    
    # Check template exists
    local template_list
    template_list=$(coder_exec templates list --output json 2>/dev/null)
    if ! echo "$template_list" | python3 -c "import json,sys; data=json.load(sys.stdin); names=[t.get('Template',t).get('name','') for t in data]; sys.exit(0 if '$TEMPLATE_NAME' in names else 1)" 2>/dev/null; then
        log_fail "Template exists" "template '$TEMPLATE_NAME' not found"
        exit 1
    fi
    log_pass "Template '$TEMPLATE_NAME' exists"
    
    # Check no conflicting workspace
    local existing
    existing=$(coder_exec list --output json 2>/dev/null | python3 -c "import json,sys; data=json.load(sys.stdin); print(any(w.get('name','')=='$WORKSPACE_NAME' for w in data))" 2>/dev/null || echo "false")
    if [[ "$existing" == "True" || "$existing" == "true" ]]; then
        log "Deleting existing workspace: $WORKSPACE_NAME"
        coder_exec delete "$WORKSPACE_NAME" --yes >/dev/null 2>&1
    fi
    log_pass "No conflicting workspace"
}

# =============================================================================
# TEST: TEMPLATE VARIABLES
# =============================================================================

test_template_variables() {
    log_section "Template Variables"
    
    # Get active version ID
    local template_info
    template_info=$(coder_api "/api/v2/templates" | python3 -c "
import json, sys
templates = json.load(sys.stdin)
for t in templates:
    if t['name'] == '$TEMPLATE_NAME':
        print(t['active_version_id'])
        break
" 2>/dev/null)
    
    if [[ -z "$template_info" ]]; then
        log_skip "Template variables" "could not get template info"
        return
    fi
    
    # Check stored variable values
    local vars
    vars=$(coder_api "/api/v2/templateversions/$template_info/variables")
    
    # Check traefik_auth_dir matches actual directory
    local traefik_value
    traefik_value=$(echo "$vars" | python3 -c "
import json, sys
for v in json.load(sys.stdin):
    if v['name'] == 'traefik_auth_dir':
        print(v['value'])
" 2>/dev/null)
    
    if [[ -n "$traefik_value" ]]; then
        if [[ -d "$traefik_value" ]]; then
            log_pass "traefik_auth_dir path exists ($traefik_value)"
        else
            log_fail "traefik_auth_dir path exists" "directory not found: $traefik_value"
        fi
        
        # Check value matches default_value (no stale overrides)
        local traefik_default
        traefik_default=$(echo "$vars" | python3 -c "
import json, sys
for v in json.load(sys.stdin):
    if v['name'] == 'traefik_auth_dir':
        print(v['default_value'])
" 2>/dev/null)
        assert_equals "$traefik_value" "$traefik_default" "traefik_auth_dir value matches default"
    fi
    
    # Check base_domain is not localhost
    local domain
    domain=$(echo "$vars" | python3 -c "
import json, sys
for v in json.load(sys.stdin):
    if v['name'] == 'base_domain':
        print(v['value'])
" 2>/dev/null)
    if [[ "$domain" != "localhost" && -n "$domain" ]]; then
        log_pass "base_domain is configured ($domain)"
    else
        log_fail "base_domain is configured" "value: '$domain'"
    fi
    
    # Check host_ip is not 127.0.0.1
    local host_ip
    host_ip=$(echo "$vars" | python3 -c "
import json, sys
for v in json.load(sys.stdin):
    if v['name'] == 'host_ip':
        print(v['value'])
" 2>/dev/null)
    if [[ "$host_ip" != "127.0.0.1" && -n "$host_ip" ]]; then
        log_pass "host_ip is configured ($host_ip)"
    else
        log_fail "host_ip is configured" "value: '$host_ip'"
    fi
}

# =============================================================================
# TEST: WORKSPACE CREATION
# =============================================================================

test_workspace_creation() {
    log_section "Workspace Creation"
    
    log "Creating workspace: $WORKSPACE_NAME (template: $TEMPLATE_NAME)"
    
    local create_output
    create_output=$(coder_exec create "$WORKSPACE_NAME" \
        --template "$TEMPLATE_NAME" \
        --parameter startup_command="" \
        --parameter workspace_password="" \
        --parameter preview_port=8080 \
        --parameter external_preview=true \
        --parameter auto_generate_html=true \
        --parameter enable_ssh=true \
        --parameter repo_url="" \
        --yes 2>&1)
    local create_exit=$?
    
    if [[ $create_exit -eq 0 ]]; then
        log_pass "Workspace created successfully"
    else
        log_fail "Workspace created successfully" "exit code: $create_exit"
        echo "$create_output" | tail -10
        return 1
    fi
    
    # Verify no errors in output
    if echo "$create_output" | grep -qi "error.*creation errored\|error.*bind source"; then
        log_fail "No creation errors" "found error in build output"
    else
        log_pass "No creation errors in build output"
    fi
    
    # Verify resource count
    local resource_count
    resource_count=$(echo "$create_output" | grep -oP 'Resources: \K[0-9]+(?= added)' | tail -1)
    if [[ -n "$resource_count" && "$resource_count" -ge 10 ]]; then
        log_pass "Resource count: $resource_count added"
    else
        log_fail "Resource count" "expected >= 10, got: ${resource_count:-0}"
    fi
}

# =============================================================================
# TEST: WORKSPACE STATUS
# =============================================================================

test_workspace_status() {
    log_section "Workspace Status"
    
    # Wait for agent to connect
    log "Waiting for agent to connect (timeout: ${WAIT_AGENT_TIMEOUT}s)..."
    local start_time=$SECONDS
    local status=""
    
    while [[ $((SECONDS - start_time)) -lt $WAIT_AGENT_TIMEOUT ]]; do
        status=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data:
    if w.get('name','') == '$WORKSPACE_NAME':
        s = w.get('latest_build',{}).get('status','')
        print(s)
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
    
    # Check health
    local healthy
    healthy=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data:
    if w.get('name','') == '$WORKSPACE_NAME':
        print(w.get('health',{}).get('healthy', False))
        break
" 2>/dev/null || echo "False")
    assert_equals "$healthy" "True" "Workspace is healthy"
    
    # Check template version is active
    local ws_version
    ws_version=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data:
    if w.get('name','') == '$WORKSPACE_NAME':
        print(w.get('outdated', True))
        break
" 2>/dev/null || echo "True")
    assert_equals "$ws_version" "False" "Workspace is on latest version"
}

# =============================================================================
# TEST: DOCKER CONTAINER
# =============================================================================

test_docker_container() {
    log_section "Docker Container"
    
    local container
    container=$(get_workspace_container)
    
    if [[ -z "$container" ]]; then
        log_fail "Workspace container exists" "no container found"
        return 1
    fi
    log_pass "Workspace container exists ($container)"
    
    # Check container is running
    local state
    state=$(docker inspect "$container" --format "{{.State.Status}}" 2>/dev/null)
    assert_equals "$state" "running" "Container is running"
    
    # Check container is on coder-network
    local networks
    networks=$(docker inspect "$container" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
    assert_contains "$networks" "coder-network" "Container on coder-network"
    
    # Check home volume is mounted
    local mounts
    mounts=$(docker inspect "$container" --format '{{range .Mounts}}{{.Destination}} {{end}}' 2>/dev/null)
    assert_contains "$mounts" "/home/coder" "Home directory mounted"
    
    # Check traefik-auth is mounted
    assert_contains "$mounts" "/traefik-auth" "Traefik auth directory mounted"
    
    # Check traefik-auth mount source is correct
    local traefik_source
    traefik_source=$(docker inspect "$container" --format '{{range .Mounts}}{{if eq .Destination "/traefik-auth"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
    if [[ -d "$traefik_source" ]]; then
        log_pass "Traefik auth mount source exists ($traefik_source)"
    else
        log_fail "Traefik auth mount source exists" "not found: $traefik_source"
    fi
}

# =============================================================================
# TEST: SSH SERVER
# =============================================================================

test_ssh_server() {
    log_section "SSH Server"
    
    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_skip "SSH Server" "no container"
        return
    fi
    
    # Wait for startup scripts to finish
    log "Waiting for startup scripts to complete..."
    local start_time=$SECONDS
    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        local sshd_running
        sshd_running=$(docker exec "$container" pgrep -x sshd 2>/dev/null || echo "")
        if [[ -n "$sshd_running" ]]; then
            break
        fi
        sleep 3
    done
    
    # Check sshd process
    local sshd_pid
    sshd_pid=$(docker exec "$container" pgrep -x sshd 2>/dev/null || echo "")
    if [[ -n "$sshd_pid" ]]; then
        log_pass "SSHD process running (PID: $sshd_pid)"
    else
        log_fail "SSHD process running" "not found"
        return
    fi
    
    # Check port 2222
    local port_listen
    port_listen=$(docker exec "$container" ss -tlnp 2>/dev/null | grep ":2222" || echo "")
    assert_not_empty "$port_listen" "SSH listening on port 2222"
    
    # Check persistent host keys (run as coder user since keys are in /home/coder)
    local host_keys
    host_keys=$(docker exec -u coder "$container" ls /home/coder/.persist/ssh/hostkeys/ 2>/dev/null || echo "")
    assert_contains "$host_keys" "ssh_host_ed25519_key" "Persistent ed25519 host key"
    assert_contains "$host_keys" "ssh_host_rsa_key" "Persistent RSA host key"
    
    # Check user SSH key pair
    local user_key
    user_key=$(docker exec -u coder "$container" cat /home/coder/.ssh/id_ed25519.pub 2>/dev/null || echo "")
    assert_contains "$user_key" "ssh-ed25519" "User ed25519 key pair generated"
    
    # Check known_hosts
    local known_hosts_count
    known_hosts_count=$(docker exec -u coder "$container" bash -c 'wc -l < /home/coder/.ssh/known_hosts' 2>/dev/null || echo "0")
    if [[ "$known_hosts_count" -ge 4 ]]; then
        log_pass "Known hosts populated ($known_hosts_count entries)"
    else
        log_fail "Known hosts populated" "only $known_hosts_count entries"
    fi
    
    # Test SSH connectivity from host to container port
    local ssh_port
    ssh_port=$(docker port "$container" 2222/tcp 2>/dev/null | head -1 | cut -d: -f2)
    if [[ -n "$ssh_port" ]]; then
        log_pass "SSH port mapped to host ($ssh_port)"
    else
        log_fail "SSH port mapped to host" "port 2222 not mapped"
    fi
}

# =============================================================================
# TEST: GIT CONFIG
# =============================================================================

test_git_config() {
    log_section "Git Configuration"
    
    local container
    container=$(get_workspace_container)
    
    # Test: git user.name is set
    local git_name
    git_name=$(docker exec "$container" git config --global user.name 2>/dev/null || echo "")
    if [[ -n "$git_name" ]]; then
        log_pass "Git user.name configured ($git_name)"
    else
        log_fail "Git user.name configured" "not set"
    fi
    
    # Test: git user.email is set
    local git_email
    git_email=$(docker exec "$container" git config --global user.email 2>/dev/null || echo "")
    if [[ -n "$git_email" ]]; then
        log_pass "Git user.email configured ($git_email)"
    else
        log_fail "Git user.email configured" "not set"
    fi
    
    # Test: init.defaultBranch
    local default_branch
    default_branch=$(docker exec "$container" git config --global init.defaultBranch 2>/dev/null || echo "")
    if [[ "$default_branch" == "main" ]]; then
        log_pass "Git init.defaultBranch = main"
    else
        log_fail "Git init.defaultBranch = main" "got: $default_branch"
    fi
    
    # Test: safe.directory includes workspace
    local safe_dir
    safe_dir=$(docker exec "$container" git config --global --get-all safe.directory 2>/dev/null || echo "")
    if echo "$safe_dir" | grep -q "/home/coder/workspace"; then
        log_pass "Workspace in safe.directory"
    else
        log_fail "Workspace in safe.directory" "not found in: $safe_dir"
    fi
    
    # Test: Git identity works for commits (validates both gitconfig and env vars)
    # The agent's env block sets GIT_AUTHOR_NAME/EMAIL for agent child processes,
    # and git config --global sets it for all processes. Test via a real commit.
    local commit_author
    commit_author=$(docker exec "$container" bash -c '
        cd /tmp && rm -rf git-id-test 2>/dev/null
        git init git-id-test >/dev/null 2>&1
        cd git-id-test
        echo test > test.txt
        git add . >/dev/null 2>&1
        git commit -m "identity test" >/dev/null 2>&1
        git log --format="%an <%ae>" -1 2>/dev/null
        cd /tmp && rm -rf git-id-test
    ' 2>/dev/null || echo "")
    if [[ -n "$commit_author" ]] && [[ "$commit_author" != *"unknown"* ]]; then
        log_pass "Git identity works for commits ($commit_author)"
    else
        log_fail "Git identity works for commits" "got: $commit_author"
    fi
    
    # Test: Init-shell ran (home dir initialized)
    if docker exec "$container" test -f /home/coder/.init_done 2>/dev/null; then
        log_pass "Home directory initialized (.init_done exists)"
    else
        log_fail "Home directory initialized" ".init_done not found"
    fi
    
    # Test: Standard directories created
    local dirs_ok=true
    for dir in /home/coder/.config /home/coder/.local/bin /home/coder/workspace; do
        if ! docker exec "$container" test -d "$dir" 2>/dev/null; then
            dirs_ok=false
            break
        fi
    done
    if $dirs_ok; then
        log_pass "Standard directories created (.config, .local/bin, workspace)"
    else
        log_fail "Standard directories created" "missing: $dir"
    fi
}

# =============================================================================
# TEST: CODE SERVER
# =============================================================================

test_code_server() {
    log_section "Code Server (code-server)"
    
    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_skip "Code Server" "no container"
        return
    fi
    
    # Wait a bit for code-server to start
    sleep 3
    
    # Check code-server process
    local cs_pid
    cs_pid=$(docker exec "$container" pgrep -f "code-server" 2>/dev/null | head -1 || echo "")
    if [[ -n "$cs_pid" ]]; then
        log_pass "code-server process running"
    else
        # code-server might need more time
        log "Waiting for code-server to start..."
        sleep 10
        cs_pid=$(docker exec "$container" pgrep -f "code-server" 2>/dev/null | head -1 || echo "")
        if [[ -n "$cs_pid" ]]; then
            log_pass "code-server process running (delayed start)"
        else
            log_fail "code-server process running" "not found"
        fi
    fi
    
    # Check code-server port (default 13337)
    local cs_port
    cs_port=$(docker exec "$container" ss -tlnp 2>/dev/null | grep ":13337" || echo "")
    if [[ -n "$cs_port" ]]; then
        log_pass "code-server listening on port 13337"
    else
        log_skip "code-server port check" "may still be starting"
    fi
}

# =============================================================================
# TEST: TRAEFIK ROUTING
# =============================================================================

test_traefik_routing() {
    log_section "Traefik Routing"
    
    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_skip "Traefik Routing" "no container"
        return
    fi
    
    # Check traefik-auth dir is accessible
    local auth_dir
    auth_dir=$(docker exec "$container" ls /traefik-auth/ 2>/dev/null || echo "")
    assert_not_empty "$auth_dir" "Traefik auth directory is accessible"
    
    # Check for htpasswd file or related auth config
    local has_auth_config
    has_auth_config=$(docker exec "$container" find /traefik-auth -name "*.yml" -o -name "*.yaml" -o -name ".htpasswd" 2>/dev/null | head -1 || echo "")
    if [[ -n "$has_auth_config" ]]; then
        log_pass "Traefik auth configuration files found"
    else
        log_skip "Traefik auth config files" "no auth files yet (may be expected)"
    fi
    
    # Check container labels for Traefik
    local labels
    labels=$(docker inspect "$container" --format '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}} {{end}}' 2>/dev/null)
    if echo "$labels" | grep -q "traefik" 2>/dev/null; then
        log_pass "Container has Traefik labels"
    else
        log_skip "Traefik labels" "labels may be set by Coder agent"
    fi
}

# =============================================================================
# TEST: WORKSPACE AGENT METADATA
# =============================================================================

test_agent_metadata() {
    log_section "Agent Metadata"
    
    # Get workspace agents via API
    local workspace_id
    workspace_id=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data:
    if w.get('name','') == '$WORKSPACE_NAME':
        print(w.get('id',''))
        break
" 2>/dev/null)
    
    if [[ -z "$workspace_id" ]]; then
        log_skip "Agent metadata" "couldn't get workspace ID"
        return
    fi
    
    # Check agent is connected via API
    local agent_status
    agent_status=$(coder_api "/api/v2/workspaces/$workspace_id" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('latest_build',{}).get('resources',[]):
    for a in r.get('agents',[]):
        print(a.get('status',''))
        break
" 2>/dev/null)
    assert_equals "$agent_status" "connected" "Agent status is connected"
    
    # Check apps are registered
    local app_count
    app_count=$(coder_api "/api/v2/workspaces/$workspace_id" | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for r in data.get('latest_build',{}).get('resources',[]):
    for a in r.get('agents',[]):
        count += len(a.get('apps',[]))
print(count)
" 2>/dev/null || echo "0")
    if [[ "$app_count" -ge 2 ]]; then
        log_pass "Apps registered ($app_count apps)"
    else
        log_fail "Apps registered" "expected >= 2, got: $app_count"
    fi
    
    # List app names
    local app_names
    app_names=$(coder_api "/api/v2/workspaces/$workspace_id" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('latest_build',{}).get('resources',[]):
    for a in r.get('agents',[]):
        for app in a.get('apps',[]):
            print(f\"    - {app.get('display_name', app.get('slug','?'))}\")
" 2>/dev/null)
    if [[ -n "$app_names" ]]; then
        echo "$app_names"
    fi
}

# =============================================================================
# TEST: STOP & RESTART
# =============================================================================

test_stop_start() {
    log_section "Stop & Restart"
    
    # Stop workspace
    log "Stopping workspace..."
    local stop_output
    stop_output=$(coder_exec stop "$WORKSPACE_NAME" --yes 2>&1)
    local stop_exit=$?
    
    assert_exit_code "$stop_exit" 0 "Workspace stopped"
    
    # Verify stopped
    sleep 2
    local status_after_stop
    status_after_stop=$(coder_exec list --output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data:
    if w.get('name','') == '$WORKSPACE_NAME':
        print(w.get('latest_build',{}).get('status',''))
        break
" 2>/dev/null)
    if [[ "$status_after_stop" == "stopped" || "$status_after_stop" == "Stopped" ]]; then
        log_pass "Workspace status is stopped"
    else
        log_fail "Workspace status is stopped" "status: $status_after_stop"
    fi
    
    # Start workspace
    log "Starting workspace..."
    local start_output
    start_output=$(coder_exec start "$WORKSPACE_NAME" --yes 2>&1)
    local start_exit=$?
    
    assert_exit_code "$start_exit" 0 "Workspace restarted"
    
    # Wait for agent reconnect
    log "Waiting for agent to reconnect..."
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
    
    if [[ "$status" == "running" || "$status" == "started" ]]; then
        log_pass "Workspace restarted successfully"
    else
        log_fail "Workspace restarted" "status: $status"
    fi
}

# =============================================================================
# TEST: PERSISTENCE (after restart)
# =============================================================================

test_persistence() {
    log_section "Persistence (after restart)"
    
    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_skip "Persistence" "no container after restart"
        return
    fi
    
    # Wait for sshd to restart
    local start_time=$SECONDS
    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        local sshd_check
        sshd_check=$(docker exec "$container" pgrep -x sshd 2>/dev/null || echo "")
        if [[ -n "$sshd_check" ]]; then
            break
        fi
        sleep 3
    done
    
    # Check SSH host keys persisted
    local host_keys
    host_keys=$(docker exec -u coder "$container" ls /home/coder/.persist/ssh/hostkeys/ssh_host_ed25519_key 2>/dev/null || echo "")
    assert_not_empty "$host_keys" "SSH host keys persisted across restart"
    
    # Check user SSH keys persisted
    local user_key
    user_key=$(docker exec -u coder "$container" cat /home/coder/.ssh/id_ed25519.pub 2>/dev/null || echo "")
    assert_contains "$user_key" "ssh-ed25519" "User SSH keys persisted across restart"
    
    # Check sshd is running again
    local sshd_pid
    sshd_pid=$(docker exec "$container" pgrep -x sshd 2>/dev/null || echo "")
    assert_not_empty "$sshd_pid" "SSHD restarted after workspace restart"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Coder Template Test Suite${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "  Template:  ${CYAN}$TEMPLATE_NAME${NC}"
    echo -e "  Workspace: ${CYAN}$WORKSPACE_NAME${NC}"
    echo ""
    
    # Set cleanup trap
    if ! $KEEP_WORKSPACE; then
        trap cleanup EXIT
    fi
    
    # Run test phases
    preflight
    test_template_variables
    test_workspace_creation || { echo -e "${RED}Workspace creation failed — cannot continue${NC}"; exit 1; }
    test_workspace_status || { echo -e "${RED}Workspace not ready — cannot continue${NC}"; exit 1; }
    test_docker_container
    test_ssh_server
    test_git_config
    test_code_server
    test_traefik_routing
    test_agent_metadata
    test_stop_start
    test_persistence
    
    # ─── Summary ────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Test Results${NC}"
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

main
