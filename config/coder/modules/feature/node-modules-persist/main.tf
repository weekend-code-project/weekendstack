# =============================================================================
# MODULE: Node Modules Persistence
# =============================================================================
# Persists node_modules directories across workspace restarts using a
# separate Docker volume. This prevents node_modules from consuming space
# in the home directory volume (useful when home is on a small local drive).
#
# How it works:
#   1. Creates a dedicated Docker volume for node_modules storage
#   2. At startup, bind-mounts persistent storage to each node_modules path
#   3. Detects lock files and runs the correct package manager install
#   4. Uses hash-based sentinel to skip installs when deps haven't changed
#
# This module outputs a Docker volume and a startup script.
# The template must wire the volume into the container and run the script.
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "workspace_name" {
  description = "Workspace name (used for volume naming)"
  type        = string
}

variable "owner_name" {
  description = "Owner name (used for volume naming)"
  type        = string
}

variable "workspace_folder" {
  description = "The workspace folder path"
  type        = string
  default     = "/home/coder/workspace"
}

variable "node_modules_paths" {
  description = "Comma-separated relative paths for node_modules dirs (e.g., 'node_modules,frontend/node_modules')"
  type        = string
  default     = "node_modules"
}

variable "enabled" {
  description = "Whether to enable node_modules persistence. When false, node_modules lives in the workspace as normal."
  type        = bool
  default     = false
}

# =============================================================================
# Locals
# =============================================================================

locals {
  nm_paths = var.enabled ? [
    for p in split(",", coalesce(var.node_modules_paths, "")) :
    trimsuffix(trimspace(p), "/")
    if length(trimspace(p)) > 0
  ] : []

  persist_folder = "/home/coder/.persist"
}

# =============================================================================
# Persistent Volume for node_modules
# =============================================================================

resource "docker_volume" "node_modules" {
  count = var.enabled ? 1 : 0
  name  = "coder-${var.owner_name}-${var.workspace_name}-nodemodules"
}

# =============================================================================
# Startup Script (coder_script)
# =============================================================================

resource "coder_script" "node_modules_persist" {
  count = var.enabled ? 1 : 0

  agent_id           = var.agent_id
  display_name       = "Node Modules Persist"
  icon               = "/icon/nodejs.svg"
  run_on_start       = true
  start_blocks_login = true  # Must complete before dev can use workspace

  script = <<-EOT
    #!/bin/bash
    set -e

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[NODE-MODULES] Setting up persistent node_modules..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    PERSIST_ROOT="${local.persist_folder}/node_modules"
    WORKSPACE_DIR="${var.workspace_folder}"

    # Wait for Node.js to be available
    MAX_WAIT=120
    WAITED=0
    while ! command -v node >/dev/null 2>&1; do
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[NODE-MODULES] WARNING: Node.js not available after $${MAX_WAIT}s"
        break
      fi
      sleep 2
      WAITED=$((WAITED + 2))
      # Source NVM if it exists
      if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        \. "$NVM_DIR/nvm.sh"
      fi
    done

    mkdir -p "$PERSIST_ROOT"
    chmod 755 "$PERSIST_ROOT"

    %{ for path in local.nm_paths ~}
    # ── Process: ${path} ──
    echo "[NODE-MODULES] Processing: ${path}"
    NM_PATH="${path}"

    TARGET="$WORKSPACE_DIR/$NM_PATH"
    SAFE_NAME="$(echo "$NM_PATH" | sed 's#/#_#g')"
    PERSIST_PATH="$PERSIST_ROOT/$SAFE_NAME"

    # Create directories
    mkdir -p "$PERSIST_PATH"
    mkdir -p "$TARGET"

    # If target is already a symlink, remove it
    if [ -L "$TARGET" ]; then
      rm -f "$TARGET"
      mkdir -p "$TARGET"
    fi

    # Copy existing node_modules to persist dir if persist is empty and target has content
    if [ -z "$(ls -A "$PERSIST_PATH" 2>/dev/null)" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
      echo "[NODE-MODULES] Migrating existing node_modules to persistent storage..."
      cp -a "$TARGET"/. "$PERSIST_PATH"/ 2>/dev/null || true
    fi

    # Clear the target and create symlink to persist
    rm -rf "$TARGET"
    ln -sfn "$PERSIST_PATH" "$TARGET"
    echo "[NODE-MODULES] Linked: $TARGET -> $PERSIST_PATH"

    # Install dependencies if package.json exists
    PKG_DIR="$(dirname "$TARGET")"
    if [ -f "$PKG_DIR/package.json" ]; then
      echo "[NODE-MODULES] Found package.json in $PKG_DIR"

      # Calculate hash of lock files
      LOCKHASH="$(cat "$PKG_DIR/pnpm-lock.yaml" "$PKG_DIR/yarn.lock" "$PKG_DIR/package-lock.json" 2>/dev/null | sha256sum | awk '{print $1}')"
      SENTINEL="$PERSIST_PATH/.deps_ready"
      CURRENT="$(cat "$SENTINEL" 2>/dev/null || true)"

      if [ "$LOCKHASH" != "$CURRENT" ] || [ -z "$(ls -A "$PERSIST_PATH" 2>/dev/null | grep -v '.deps_ready' | grep -v '.install.lock')" ]; then
        echo "[NODE-MODULES] Installing dependencies in $PKG_DIR..."
        cd "$PKG_DIR"

        if [ -f "$PKG_DIR/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
          echo "[NODE-MODULES] Using pnpm..."
          pnpm install 2>&1 || true
        elif [ -f "$PKG_DIR/yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
          echo "[NODE-MODULES] Using yarn..."
          yarn install 2>&1 || true
        elif [ -f "$PKG_DIR/package-lock.json" ]; then
          echo "[NODE-MODULES] Using npm ci..."
          npm ci 2>&1 || npm install 2>&1 || true
        else
          echo "[NODE-MODULES] Using npm install..."
          npm install 2>&1 || true
        fi

        echo "$LOCKHASH" > "$SENTINEL"
        echo "[NODE-MODULES] Dependencies installed"
      else
        echo "[NODE-MODULES] Dependencies up-to-date (skipping install)"
      fi
    fi

    %{ endfor ~}

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[NODE-MODULES] Done"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "volume_name" {
  description = "Docker volume name for persistent node_modules (empty when disabled)"
  value       = var.enabled ? docker_volume.node_modules[0].name : ""
}

output "volume_mount_path" {
  description = "Container path where the node_modules volume should be mounted"
  value       = local.persist_folder
}

output "enabled" {
  description = "Whether persistence is enabled"
  value       = var.enabled
}
