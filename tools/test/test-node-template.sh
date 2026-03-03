#!/bin/bash
# =============================================================================
# Node Template Integration Test
# =============================================================================
# Tests the "node" Coder template with full Node.js development environment.
#
# Validates:
#   1. Workspace creation with Node.js
#   2. Node.js installed with correct version (NVM)
#   3. npm package installation works
#   4. Can create and serve a project via HTTP
#   5. Hosted file is accessible via preview port
#   6. code-server is running
#
# Usage:
#   ./tools/test/test-node-template.sh [--keep]
#
# Required:
#   CODER_SESSION_TOKEN env var must be set
# =============================================================================

set -euo pipefail

# ─── Template config ────────────────────────────────────────
TEMPLATE_NAME="node"
WAIT_SCRIPTS_TIMEOUT=180

CREATE_PARAMS=(
    --parameter node_version=lts
    --parameter package_manager=npm
    --parameter persist_node_modules=false
    --parameter startup_command=""
    --parameter preview_port=8080
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

    # Wait for NVM/Node install to finish
    log "Waiting for Node.js installation to complete..."
    local start_time=$SECONDS
    local node_ready=false

    while [[ $((SECONDS - start_time)) -lt $WAIT_SCRIPTS_TIMEOUT ]]; do
        # Source NVM and check node
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

    # Check node version
    local node_version
    node_version=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        node --version
    ' || echo "")
    assert_not_empty "$node_version" "Node version: $node_version"

    # Check npm
    local npm_version
    npm_version=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        npm --version
    ' || echo "")
    assert_not_empty "$npm_version" "npm version: $npm_version"

    # Check NVM is installed
    local nvm_dir
    nvm_dir=$(workspace_exec 'ls -la $HOME/.nvm/nvm.sh 2>/dev/null' || echo "")
    assert_not_empty "$nvm_dir" "NVM is installed (~/.nvm/nvm.sh)"
}

# =============================================================================
# TEST: npm Package Installation
# =============================================================================

test_npm_install() {
    log_section "npm Package Installation"

    # Create a simple project and install a package
    log "Creating test project and installing http-server globally..."
    local install_output
    install_output=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

        # Install http-server globally
        npm install -g http-server 2>&1
    ' || echo "FAILED")
    local install_exit=$?

    if [[ $install_exit -eq 0 ]] && ! echo "$install_output" | grep -q "ERR!"; then
        log_pass "npm install -g http-server succeeded"
    else
        log_fail "npm install -g http-server" "exit $install_exit"
        echo "  $(echo "$install_output" | tail -3)"
    fi

    # Create a test project with dependencies
    log "Creating test project with express..."
    local project_output
    project_output=$(workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

        mkdir -p /home/coder/workspace/test-project
        cd /home/coder/workspace/test-project

        # Init project
        npm init -y 2>&1

        # Install express
        npm install express 2>&1
    ' || echo "FAILED")

    # Verify node_modules exists
    local node_modules
    node_modules=$(workspace_exec "ls /home/coder/workspace/test-project/node_modules/.package-lock.json 2>/dev/null" || echo "")
    if [[ -n "$node_modules" ]]; then
        log_pass "node_modules installed (express)"
    else
        log_fail "node_modules installed" "node_modules/.package-lock.json not found"
    fi

    # Verify package.json has express
    local has_express
    has_express=$(workspace_exec "cat /home/coder/workspace/test-project/package.json 2>/dev/null | grep express" || echo "")
    assert_not_empty "$has_express" "package.json lists express as dependency"
}

# =============================================================================
# TEST: Serve and Access Hosted File
# =============================================================================

test_hosted_file() {
    log_section "Hosted File Access"

    # Create an HTML file and serve it
    log "Creating and serving test HTML file..."
    workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

        mkdir -p /home/coder/workspace/test-serve
        cat > /home/coder/workspace/test-serve/index.html <<HTMLEOF
<!DOCTYPE html>
<html>
<head><title>Node Test</title></head>
<body><h1>Hello from Node Template Test</h1></body>
</html>
HTMLEOF

        # Start http-server in background on port 8080
        cd /home/coder/workspace/test-serve
        nohup http-server -p 8080 > /tmp/http-server.log 2>&1 &
    ' || true

    # Wait for server to start
    sleep 3

    # Verify port is listening
    local listening
    listening=$(workspace_exec "ss -tlnp 2>/dev/null | grep ':8080'" || echo "")
    if [[ -n "$listening" ]]; then
        log_pass "http-server listening on port 8080"
    else
        log "Waiting for http-server to start..."
        sleep 5
        listening=$(workspace_exec "ss -tlnp 2>/dev/null | grep ':8080'" || echo "")
        if [[ -n "$listening" ]]; then
            log_pass "http-server listening on port 8080 (delayed)"
        else
            log_fail "http-server listening on port 8080" "port not open"
            workspace_exec "cat /tmp/http-server.log 2>/dev/null" || true
            return
        fi
    fi

    # Fetch the page
    local page_content
    page_content=$(workspace_exec "curl -sf http://localhost:8080/ 2>/dev/null" || echo "")
    if echo "$page_content" | grep -q "Hello from Node Template Test"; then
        log_pass "Hosted HTML file accessible via HTTP"
    else
        log_fail "Hosted HTML file accessible" "expected greeting not found"
        echo "  Response: $(echo "$page_content" | head -5)"
    fi

    # Test with express server too
    log "Testing express server..."
    workspace_exec '
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

        # Kill existing http-server
        pkill -f "http-server" 2>/dev/null || true
        sleep 1

        cd /home/coder/workspace/test-project
        cat > server.js <<JSEOF
const express = require("express");
const app = express();
app.get("/", (req, res) => res.send("Express OK"));
app.get("/health", (req, res) => res.json({ status: "healthy" }));
app.listen(8080, "0.0.0.0", () => console.log("ready"));
JSEOF
        nohup node server.js > /tmp/express.log 2>&1 &
    ' || true

    sleep 3

    local express_response
    express_response=$(workspace_exec "curl -sf http://localhost:8080/ 2>/dev/null" || echo "")
    if [[ "$express_response" == "Express OK" ]]; then
        log_pass "Express server responds correctly"
    else
        log_fail "Express server responds" "got: '$express_response'"
    fi

    local health_response
    health_response=$(workspace_exec "curl -sf http://localhost:8080/health 2>/dev/null" || echo "")
    if echo "$health_response" | grep -q "healthy"; then
        log_pass "Express health endpoint works"
    else
        log_fail "Express health endpoint" "got: '$health_response'"
    fi

    # Clean up
    workspace_exec "pkill -f 'node server.js' 2>/dev/null" || true
}

# =============================================================================
# TEST: Git Config Present (node template includes git modules)
# =============================================================================

test_git_config() {
    log_section "Git Configuration"

    local git_name
    git_name=$(workspace_exec "git config --global user.name 2>/dev/null" || echo "")
    if [[ -n "$git_name" ]]; then
        log_pass "Git user.name configured ($git_name)"
    else
        log_fail "Git user.name configured" "not set"
    fi

    local git_email
    git_email=$(workspace_exec "git config --global user.email 2>/dev/null" || echo "")
    if [[ -n "$git_email" ]]; then
        log_pass "Git user.email configured ($git_email)"
    else
        log_fail "Git user.email configured" "not set"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Node Template Test Suite${NC}"
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
    test_npm_install
    test_hosted_file
    test_code_server
    test_git_config
    print_summary
}

main
