terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "node_modules_paths" {
  type        = string
  description = "Comma-separated paths (relative to workspace folder) for node_modules directories. Example: node_modules,backend/node_modules,frontend/node_modules"
  default     = "node_modules"
}

variable "workspace_folder" {
  type        = string
  description = "The path to the workspace folder"
  default     = "/home/coder/workspace"
}

variable "persist_folder" {
  type        = string
  description = "The path to the persistence folder"
  default     = "/home/coder/.persist"
}

locals {
  nm_paths = [
    for p in split(",", coalesce(var.node_modules_paths, "")) :
    trimsuffix(trimspace(p), "/")
    if length(trimspace(p)) > 0
  ]
}

output "init_script" {
  value = <<-EOT
    echo "[NODE-MODULES] Setting up persistent node_modules directories..."
    
    # Create persistence root
    mkdir -p "${var.persist_folder}/node_modules"
    chmod 755 "${var.persist_folder}/node_modules"
    
    # Process each node_modules path
    ${join("\n", [for path in local.nm_paths : <<-SUBDIR
    echo "[NODE-MODULES] Processing: ${path}"
    
    # Normalize path (remove leading/trailing slashes)
    NM_PATH="${path}"
    NM_PATH="$${NM_PATH#/}"
    NM_PATH="$${NM_PATH%/}"
    
    # Full paths
    TARGET="${var.workspace_folder}/$${NM_PATH}"
    SAFE_NAME="$(echo "$${NM_PATH}" | sed 's#/#_#g')"
    PERSIST_PATH="${var.persist_folder}/node_modules/$${SAFE_NAME}"
    
    # Create persistence directory
    mkdir -p "$${PERSIST_PATH}"
    chmod 755 "$${PERSIST_PATH}"
    
    # Create target directory if it doesn't exist
    mkdir -p "$${TARGET}"
    
    # Unmount if already mounted (for restart scenarios)
    if mountpoint -q "$${TARGET}"; then
      echo "[NODE-MODULES] Unmounting existing mount at $${TARGET}"
      sudo umount "$${TARGET}" || true
    fi
    
    # Bind mount the persistent directory
    sudo mount --bind "$${PERSIST_PATH}" "$${TARGET}"
    echo "[NODE-MODULES] ✅ Mounted $${TARGET} -> $${PERSIST_PATH}"
    
    # Detect the package directory (parent of node_modules)
    PKG_DIR="$(dirname "$${TARGET}")"
    
    # Install dependencies if package.json exists
    if [ -f "$${PKG_DIR}/package.json" ]; then
      echo "[NODE-MODULES] Found package.json in $${PKG_DIR}"
      
      # Use flock to prevent concurrent installs
      LOCKFILE="$${TARGET}/.install.lock"
      SENTINEL="$${TARGET}/.deps_ready"
      
      # Calculate hash of lock files to detect changes
      LOCKHASH="$(cat "$${PKG_DIR}/pnpm-lock.yaml" "$${PKG_DIR}/yarn.lock" "$${PKG_DIR}/package-lock.json" 2>/dev/null | sha256sum | awk '{print $1}')"
      CURRENT="$(awk '{print $1}' "$${SENTINEL}" 2>/dev/null || true)"
      
      # Install if:
      # 1. Hash changed (dependencies updated)
      # 2. node_modules is empty (first run)
      # 3. Sentinel file missing
      (
        flock 9
        if [ "$${LOCKHASH}" != "$${CURRENT}" ] || [ -z "$(ls -A "$${TARGET}" 2>/dev/null)" ] || [ ! -f "$${SENTINEL}" ]; then
          echo "[NODE-MODULES] Installing dependencies in $${PKG_DIR}..."
          
          cd "$${PKG_DIR}"
          
          # Detect and use appropriate package manager
          if command -v pnpm >/dev/null 2>&1 && [ -f "$${PKG_DIR}/pnpm-lock.yaml" ]; then
            echo "[NODE-MODULES] Using pnpm..."
            pnpm install
          elif command -v yarn >/dev/null 2>&1 && [ -f "$${PKG_DIR}/yarn.lock" ]; then
            echo "[NODE-MODULES] Using yarn..."
            yarn install
          elif [ -f "$${PKG_DIR}/package-lock.json" ]; then
            echo "[NODE-MODULES] Using npm ci..."
            npm ci || npm install
          else
            echo "[NODE-MODULES] Using npm install..."
            npm install
          fi
          
          # Write sentinel with hash
          echo "$${LOCKHASH}" > "$${SENTINEL}"
          echo "[NODE-MODULES] ✅ Dependencies installed successfully"
        else
          echo "[NODE-MODULES] Dependencies up-to-date in $${PKG_DIR} (skipping install)"
        fi
      ) 9>"$${LOCKFILE}"
    else
      echo "[NODE-MODULES] No package.json found in $${PKG_DIR} (skipping install)"
    fi
    SUBDIR
    ])}
    
    echo "[NODE-MODULES] ✅ All node_modules directories configured"
  EOT
}

output "env" {
  value = {
    NM_PATHS = var.node_modules_paths
  }
}
