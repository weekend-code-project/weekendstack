#!/bin/bash
# =============================================================================
# Docker Template Integration Test
# =============================================================================
# Tests the "docker" Coder template which provides Docker-in-Docker workspaces.
#
# Validates:
#   1. Workspace creation (privileged container, DinD)
#   2. Docker daemon running inside workspace
#   3. Can pull and run a container inside the workspace (DinD)
#   4. Default preview URL is accessible
#   5. code-server is running
#
# Usage:
#   ./tools/test/test-docker-template.sh [--keep]
#
# Required:
#   CODER_SESSION_TOKEN env var must be set
# =============================================================================

set -euo pipefail

# ─── Template config ────────────────────────────────────────
TEMPLATE_NAME="docker"
WAIT_SCRIPTS_TIMEOUT=180  # DinD takes a while to initialize

CREATE_PARAMS=(
    --parameter startup_command=""
    --parameter preview_port=8080
    --parameter auto_generate_html=true
    --parameter external_preview=true
    --parameter workspace_password=""
    --parameter enable_ssh=true
)

# ─── Source shared helpers ───────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

# =============================================================================
# TEST: Docker-in-Docker
# =============================================================================

test_dind() {
    log_section "Docker-in-Docker"

    # Wait for Docker daemon to be running inside the workspace
    log "Waiting for Docker daemon inside workspace..."
    local start_time=$SECONDS
    local docker_ready=false

    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        if workspace_exec "docker info" &>/dev/null; then
            docker_ready=true
            break
        fi
        sleep 5
    done

    local elapsed=$((SECONDS - start_time))
    if $docker_ready; then
        log_pass "Docker daemon running inside workspace (${elapsed}s)"
    else
        log_fail "Docker daemon running inside workspace" "timed out after ${WAIT_SCRIPTS_TIMEOUT}s"
        # Show debug info
        workspace_exec_root "ps aux | grep -i docker" 2>/dev/null || true
        return 1
    fi

    # Verify docker info returns valid output
    local docker_version
    docker_version=$(workspace_exec "docker version --format '{{.Server.Version}}'" 2>/dev/null || echo "")
    assert_not_empty "$docker_version" "Docker server version ($docker_version)"

    # Test: Pull and run a container inside the workspace
    log "Pulling and running hello-world container inside workspace..."
    local run_output
    run_output=$(workspace_exec "docker run --rm hello-world 2>&1" || echo "FAILED")

    if echo "$run_output" | grep -q "Hello from Docker"; then
        log_pass "Can run containers inside workspace (hello-world)"
    else
        log_fail "Can run containers inside workspace" "hello-world did not print expected message"
        echo "  Output: $(echo "$run_output" | head -5)"
    fi

    # Test: Run an nginx container and verify it serves content
    log "Running nginx container inside workspace..."
    workspace_exec "docker run -d --name dind-nginx -p 9090:80 nginx:alpine" &>/dev/null || true
    sleep 3

    local nginx_response
    nginx_response=$(workspace_exec "curl -sf http://localhost:9090/ 2>/dev/null | head -5" || echo "")
    if echo "$nginx_response" | grep -qi "nginx\|welcome"; then
        log_pass "Nested container serves HTTP content (nginx)"
    else
        log_fail "Nested container serves HTTP content" "no valid response from nginx"
    fi

    # Cleanup nested container
    workspace_exec "docker rm -f dind-nginx" &>/dev/null || true
}

# =============================================================================
# TEST: Docker Data Persistence Volume
# =============================================================================

test_docker_data_volume() {
    log_section "Docker Data Volume"

    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_skip "Docker data volume" "no container found"
        return
    fi

    local mounts
    mounts=$(docker inspect "$container" --format '{{range .Mounts}}{{.Destination}} {{end}}' 2>/dev/null)
    assert_contains "$mounts" "/var/lib/docker" "Docker data volume mounted at /var/lib/docker"
}

# =============================================================================
# TEST: Privileged Container
# =============================================================================

test_privileged() {
    log_section "Privileged Mode"

    local container
    container=$(get_workspace_container)
    if [[ -z "$container" ]]; then
        log_skip "Privileged mode" "no container found"
        return
    fi

    local is_privileged
    is_privileged=$(docker inspect "$container" --format '{{.HostConfig.Privileged}}' 2>/dev/null)
    assert_equals "$is_privileged" "true" "Container is privileged"
}

# =============================================================================
# TEST: Default Preview URL
# =============================================================================

test_preview_url() {
    log_section "Default Preview URL"

    # Wait for auto-generated HTML page or startup command
    sleep 5

    # Check if something is listening on the preview port (8080)
    local listening
    listening=$(workspace_exec "ss -tlnp 2>/dev/null | grep ':8080'" || echo "")
    if [[ -n "$listening" ]]; then
        log_pass "Service listening on preview port 8080"
    else
        # If auto_generate_html is true, http-server or python should start
        log "Port 8080 not yet open, waiting..."
        sleep 15
        listening=$(workspace_exec "ss -tlnp 2>/dev/null | grep ':8080'" || echo "")
        if [[ -n "$listening" ]]; then
            log_pass "Service listening on preview port 8080 (delayed)"
        else
            log_fail "Service listening on preview port 8080" "nothing on port 8080"
            return
        fi
    fi

    # Test HTTP response
    local response
    response=$(workspace_exec "curl -sf http://localhost:8080/ 2>/dev/null | head -20" || echo "")
    if [[ -n "$response" ]]; then
        log_pass "Preview URL returns content"
        if echo "$response" | grep -qi "html\|<!doctype\|Welcome"; then
            log_pass "Preview URL returns HTML content"
        else
            log_skip "Preview URL HTML check" "content is not HTML (may be expected)"
        fi
    else
        log_fail "Preview URL returns content" "empty response from localhost:8080"
    fi
}

# =============================================================================
# TEST: No Git Modules (docker template should not have git)
# =============================================================================

test_no_git_config() {
    log_section "No Git Config (by design)"

    # The docker template does NOT include git-config or git-platform-cli
    # Verify git config is NOT set up (default state)
    local git_name
    git_name=$(workspace_exec "git config --global user.name 2>/dev/null" || echo "")
    if [[ -z "$git_name" ]]; then
        log_pass "Git user.name is not configured (expected — no git module)"
    else
        log_skip "Git user.name check" "git user.name is set ($git_name) — may come from base image"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Docker Template Test Suite${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "  Template:  ${CYAN}$TEMPLATE_NAME${NC}"
    echo -e "  Workspace: ${CYAN}$WORKSPACE_NAME${NC}"
    echo ""

    if ! $KEEP_WORKSPACE; then
        trap cleanup EXIT
    fi

    preflight
    create_workspace || { echo -e "${RED}Workspace creation failed${NC}"; exit 1; }
    wait_for_workspace || { echo -e "${RED}Workspace not ready${NC}"; exit 1; }
    test_container_basics
    test_privileged
    test_docker_data_volume
    test_dind
    test_preview_url
    test_code_server
    test_no_git_config
    print_summary
}

main
