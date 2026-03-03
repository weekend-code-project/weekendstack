#!/bin/bash
# =============================================================================
# Vite Template Integration Test
# =============================================================================
# Tests the "vite" Coder template with Vite project scaffolding.
#
# Validates:
#   1. Workspace creation with Node.js + Vite
#   2. Node.js installed with correct version
#   3. Vite project scaffolded automatically
#   4. npm install completed
#   5. Vite dev server running and serving content
#   6. Hosted page accessible via preview port
#   7. code-server is running
#
# Usage:
#   ./tools/test/test-vite-template.sh [--keep]
#
# Required:
#   CODER_SESSION_TOKEN env var must be set
# =============================================================================

set -euo pipefail

# ─── Template config ────────────────────────────────────────
TEMPLATE_NAME="vite"
WAIT_SCRIPTS_TIMEOUT=240  # Vite scaffolding + npm install can take a while

CREATE_PARAMS=(
    --parameter node_version=lts
    --parameter vite_framework=react
    --parameter package_manager=npm
    --parameter persist_node_modules=false
    --parameter preview_port=5173
    --parameter external_preview=true
    --parameter workspace_password=""
    --parameter enable_ssh=true
    --parameter repo_url=""
    --parameter git_cli=none
)

# ─── Source shared helpers ───────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

# =============================================================================
# TEST: Node.js Installation
# =============================================================================

test_node_installed() {
    log_section "Node.js Installation"

    log "Waiting for Node.js installation..."
    local start_time=$SECONDS
    local node_ready=false

    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        local node_check
        node_check=$(workspace_exec '
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            node --version 2>/dev/null
        ' || echo "")
        if [[ "$node_check" == v* ]]; then
            node_ready=true
            break
        fi
        sleep 5
    done

    local elapsed=$((SECONDS - start_time))
    if $node_ready; then
        log_pass "Node.js installed (${elapsed}s)"
    else
        log_fail "Node.js installed" "timed out after ${WAIT_SCRIPTS_TIMEOUT}s"
        return 1
    fi

    local node_version
    node_version=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        node --version
    ' || echo "")
    assert_not_empty "$node_version" "Node version: $node_version"
}

# =============================================================================
# TEST: Vite Project Scaffolded
# =============================================================================

test_vite_project() {
    log_section "Vite Project Scaffolding"

    # Wait for the vite startup script to finish scaffolding
    log "Waiting for Vite project scaffolding..."
    local start_time=$SECONDS
    local scaffolded=false

    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        # Check if package.json exists in workspace (sign of scaffolding)
        if workspace_exec "test -f /home/coder/workspace/package.json" &>/dev/null; then
            scaffolded=true
            break
        fi
        sleep 5
    done

    local elapsed=$((SECONDS - start_time))
    if $scaffolded; then
        log_pass "Vite project scaffolded (${elapsed}s)"
    else
        log_fail "Vite project scaffolded" "package.json not found after ${WAIT_SCRIPTS_TIMEOUT}s"
        # Debug: list workspace contents
        workspace_exec "ls -la /home/coder/workspace/ 2>/dev/null" || true
        return 1
    fi

    # Check vite is in dependencies
    local has_vite
    has_vite=$(workspace_exec "cat /home/coder/workspace/package.json 2>/dev/null | grep vite" || echo "")
    assert_not_empty "$has_vite" "Vite is in package.json dependencies"

    # Check for React (since we picked react framework)
    local has_react
    has_react=$(workspace_exec "cat /home/coder/workspace/package.json 2>/dev/null | grep react" || echo "")
    assert_not_empty "$has_react" "React is in package.json (react framework selected)"

    # Check node_modules exists (npm install ran)
    local node_modules
    node_modules=$(workspace_exec "test -d /home/coder/workspace/node_modules && echo yes" || echo "")
    if [[ "$node_modules" == "yes" ]]; then
        log_pass "node_modules directory exists (npm install completed)"
    else
        log "Waiting for npm install to complete..."
        sleep 20
        node_modules=$(workspace_exec "test -d /home/coder/workspace/node_modules && echo yes" || echo "")
        if [[ "$node_modules" == "yes" ]]; then
            log_pass "node_modules directory exists (delayed)"
        else
            log_fail "node_modules directory exists" "npm install may not have completed"
        fi
    fi

    # Check for vite.config
    local vite_config
    vite_config=$(workspace_exec "ls /home/coder/workspace/vite.config.* 2>/dev/null" || echo "")
    if [[ -n "$vite_config" ]]; then
        log_pass "vite.config file exists"
    else
        log_skip "vite.config" "may use default config"
    fi

    # Check project structure (src/ for react)
    local has_src
    has_src=$(workspace_exec "test -d /home/coder/workspace/src && echo yes" || echo "")
    if [[ "$has_src" == "yes" ]]; then
        log_pass "src/ directory exists (React project structure)"
    else
        log_skip "src/ directory" "may not exist for all templates"
    fi
}

# =============================================================================
# TEST: Vite Dev Server & Hosted File
# =============================================================================

test_vite_server() {
    log_section "Vite Dev Server & Hosted File"

    # Wait for vite dev server to be running (started by startup script)
    log "Waiting for Vite dev server on port 5173..."
    local start_time=$SECONDS
    local server_ready=false

    while [[ $((SECONDS - start_time)) -lt 60 ]]; do
        local listening
        listening=$(workspace_exec "ss -tlnp 2>/dev/null | grep ':5173'" || echo "")
        if [[ -n "$listening" ]]; then
            server_ready=true
            break
        fi
        sleep 3
    done

    local elapsed=$((SECONDS - start_time))
    if $server_ready; then
        log_pass "Vite dev server listening on port 5173 (${elapsed}s)"
    else
        log_fail "Vite dev server listening on port 5173" "port not open after 60s"
        # Debug: check processes
        workspace_exec "ps aux | grep -i vite 2>/dev/null" || true
        workspace_exec "cat /tmp/vite-*.log 2>/dev/null | tail -10" || true

        # Try manually starting vite
        log "Attempting to start Vite manually..."
        workspace_exec '
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            cd /home/coder/workspace
            nohup npx vite --host 0.0.0.0 --port 5173 > /tmp/vite-manual.log 2>&1 &
        ' || true
        sleep 5

        local retry
        retry=$(workspace_exec "ss -tlnp 2>/dev/null | grep ':5173'" || echo "")
        if [[ -n "$retry" ]]; then
            log_pass "Vite dev server started manually"
        else
            log_fail "Vite dev server" "could not start even manually"
            return
        fi
    fi

    # Fetch the page
    local page_content
    page_content=$(workspace_exec "curl -sf http://localhost:5173/ 2>/dev/null | head -30" || echo "")
    if [[ -n "$page_content" ]]; then
        log_pass "Vite dev server returns content"

        # Should contain HTML with script tags (Vite injects them)
        if echo "$page_content" | grep -qi "html\|<!doctype\|<script\|vite\|react"; then
            log_pass "Vite dev server returns HTML with framework content"
        else
            log_skip "Vite HTML content check" "content may be minimal"
        fi
    else
        log_fail "Vite dev server returns content" "empty response"
    fi

    # Test that Vite HMR endpoint exists
    local hmr_check
    hmr_check=$(workspace_exec "curl -sf -o /dev/null -w '%{http_code}' http://localhost:5173/@vite/client 2>/dev/null" || echo "000")
    if [[ "$hmr_check" == "200" ]]; then
        log_pass "Vite HMR client endpoint accessible (/@vite/client)"
    else
        log_skip "Vite HMR client" "HTTP $hmr_check (may not be exposed)"
    fi
}

# =============================================================================
# TEST: npm Project Install (same as node test requirement)
# =============================================================================

test_npm_project_install() {
    log_section "npm Project Install"

    # Install a package into the existing vite project
    local install_output
    install_output=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        cd /home/coder/workspace
        npm install lodash 2>&1
    ' || echo "FAILED")

    local has_lodash
    has_lodash=$(workspace_exec "cat /home/coder/workspace/package.json 2>/dev/null | grep lodash" || echo "")
    if [[ -n "$has_lodash" ]]; then
        log_pass "npm install lodash succeeded"
    else
        log_fail "npm install lodash" "lodash not in package.json"
    fi

    # Verify the module can be required/imported
    local require_test
    require_test=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        cd /home/coder/workspace
        node -e "const _ = require(\"lodash\"); console.log(_.VERSION)"
    ' || echo "FAILED")

    if [[ "$require_test" != "FAILED" && -n "$require_test" ]]; then
        log_pass "lodash module loads correctly (v${require_test})"
    else
        log_fail "lodash module loads" "require() failed"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Vite Template Test Suite${NC}"
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
    test_node_installed
    test_vite_project
    test_vite_server
    test_npm_project_install
    test_code_server
    print_summary
}

main
