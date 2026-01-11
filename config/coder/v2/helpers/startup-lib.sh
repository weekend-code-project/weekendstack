#!/bin/bash
# =============================================================================
# STARTUP LIBRARY - Shared Functions for Module Startup Scripts
# =============================================================================
# This library is embedded into compiled startup scripts by push-template.sh.
# All functions use the wcp_ prefix to avoid collisions.
#
# Usage (in module startup.part.sh):
#   wcp_log INFO "Starting setup..."
#   wcp_run_once my_setup_function
# =============================================================================

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

# Log with level and message
# Usage: wcp_log INFO "message"
wcp_log() {
    local level="${1:-INFO}"
    local msg="${2:-}"
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        INFO)  echo "[${timestamp}] ℹ️  $msg" ;;
        WARN)  echo "[${timestamp}] ⚠️  $msg" ;;
        ERROR) echo "[${timestamp}] ❌ $msg" ;;
        OK)    echo "[${timestamp}] ✅ $msg" ;;
        DEBUG) [[ "${WCP_DEBUG:-0}" == "1" ]] && echo "[${timestamp}] 🔍 $msg" ;;
        *)     echo "[${timestamp}] $msg" ;;
    esac
}

# Log section header
wcp_section() {
    local title="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# -----------------------------------------------------------------------------
# Idempotency - Run Once Helpers
# -----------------------------------------------------------------------------

# Directory for sentinel files
WCP_SENTINEL_DIR="${HOME}/.wcp/steps"

# Check if a step has been completed
# Usage: if wcp_is_done "step-name"; then echo "skip"; fi
wcp_is_done() {
    local step_name="$1"
    [[ -f "${WCP_SENTINEL_DIR}/${step_name}.done" ]]
}

# Mark a step as completed
# Usage: wcp_mark_done "step-name"
wcp_mark_done() {
    local step_name="$1"
    mkdir -p "$WCP_SENTINEL_DIR"
    touch "${WCP_SENTINEL_DIR}/${step_name}.done"
}

# Clear a step's completion status (for re-running)
# Usage: wcp_clear_done "step-name"
wcp_clear_done() {
    local step_name="$1"
    rm -f "${WCP_SENTINEL_DIR}/${step_name}.done"
}

# Run a function only once (skip if sentinel exists)
# Usage: wcp_run_once step_function_name
wcp_run_once() {
    local func_name="$1"
    local step_name="${func_name#wcp__mod_}"  # Strip prefix for cleaner sentinel names
    
    if wcp_is_done "$step_name"; then
        wcp_log DEBUG "Skipping $step_name (already completed)"
        return 0
    fi
    
    wcp_log INFO "Running $step_name..."
    local start_time
    start_time=$(date +%s)
    
    if "$func_name"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        wcp_mark_done "$step_name"
        wcp_log OK "$step_name completed (${duration}s)"
        return 0
    else
        local exit_code=$?
        wcp_log ERROR "$step_name failed (exit code: $exit_code)"
        return $exit_code
    fi
}

# Run a function every time (no idempotency)
# Usage: wcp_run_always my_function
wcp_run_always() {
    local func_name="$1"
    wcp_log INFO "Running $func_name..."
    if "$func_name"; then
        wcp_log OK "$func_name completed"
        return 0
    else
        wcp_log ERROR "$func_name failed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Environment Helpers
# -----------------------------------------------------------------------------

# Check if a command exists
# Usage: if wcp_has_command docker; then ...
wcp_has_command() {
    command -v "$1" &>/dev/null
}

# Wait for a command to become available
# Usage: wcp_wait_for_command docker 30
wcp_wait_for_command() {
    local cmd="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    while ! command -v "$cmd" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            wcp_log ERROR "Timeout waiting for command: $cmd"
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    wcp_log DEBUG "Command $cmd is available"
    return 0
}

# Wait for a file to exist
# Usage: wcp_wait_for_file /var/run/docker.sock 30
wcp_wait_for_file() {
    local file="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    while [[ ! -e "$file" ]]; do
        if [[ $elapsed -ge $timeout ]]; then
            wcp_log ERROR "Timeout waiting for file: $file"
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    wcp_log DEBUG "File $file exists"
    return 0
}

# -----------------------------------------------------------------------------
# File Helpers
# -----------------------------------------------------------------------------

# Ensure a directory exists
# Usage: wcp_ensure_dir /home/coder/workspace
wcp_ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        wcp_log DEBUG "Created directory: $dir"
    fi
}

# Write content to file only if different
# Usage: wcp_write_if_changed /path/to/file "content"
wcp_write_if_changed() {
    local file="$1"
    local content="$2"
    local current=""
    
    if [[ -f "$file" ]]; then
        current=$(cat "$file")
    fi
    
    if [[ "$current" != "$content" ]]; then
        echo "$content" > "$file"
        wcp_log DEBUG "Updated file: $file"
        return 0
    else
        wcp_log DEBUG "File unchanged: $file"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Port Helpers
# -----------------------------------------------------------------------------

# Parse PORTS environment variable into array
# Usage: ports=($(wcp_parse_ports))
wcp_parse_ports() {
    local ports_var="${PORTS:-8080}"
    echo "$ports_var" | tr ',' ' '
}

# Get the primary port (first in PORTS list)
# Usage: primary_port=$(wcp_primary_port)
wcp_primary_port() {
    local ports_var="${PORTS:-8080}"
    echo "${ports_var%%,*}"
}

# Check if a port is in use
# Usage: if wcp_port_in_use 8080; then ...
wcp_port_in_use() {
    local port="$1"
    netstat -tuln 2>/dev/null | grep -q ":${port} " || \
    ss -tuln 2>/dev/null | grep -q ":${port} "
}

# -----------------------------------------------------------------------------
# Git Helpers
# -----------------------------------------------------------------------------

# Check if current directory is a git repo
wcp_is_git_repo() {
    git rev-parse --git-dir &>/dev/null
}

# Get git remote URL
wcp_git_remote_url() {
    git remote get-url origin 2>/dev/null || echo ""
}
