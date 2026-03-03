# =============================================================================
# MODULE: Node Tooling
# =============================================================================
# Installs optional global Node.js packages and configures cache directories.
#
# Features:
#   - Toggle TypeScript, ESLint, http-server installs
#   - Extra packages list for custom globals
#   - Configures npm/pnpm/yarn cache directories for persistence
#   - Uses chosen package manager for global installs
#
# This module creates a `coder_script` that runs at workspace startup.
# It is self-contained and can be used in any template.
# Depends on Node.js being installed first (pair with node-version module).
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
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

variable "enable_typescript" {
  description = "Install TypeScript globally"
  type        = bool
  default     = false
}

variable "enable_eslint" {
  description = "Install ESLint globally"
  type        = bool
  default     = false
}

variable "enable_http_server" {
  description = "Install http-server globally"
  type        = bool
  default     = false
}

variable "extra_packages" {
  description = "Additional npm packages to install globally (space-separated)"
  type        = string
  default     = ""
}

variable "package_manager" {
  description = "Package manager to use for global installs: npm | pnpm | yarn"
  type        = string
  default     = "npm"

  validation {
    condition     = contains(["npm", "pnpm", "yarn"], var.package_manager)
    error_message = "package_manager must be one of: npm, pnpm, yarn"
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Build the list of packages to install
  packages = compact(concat(
    var.enable_typescript  ? ["typescript"] : [],
    var.enable_eslint      ? ["eslint"] : [],
    var.enable_http_server ? ["http-server"] : [],
    var.extra_packages != "" ? split(" ", trimspace(var.extra_packages)) : []
  ))

  has_packages = length(local.packages) > 0
}

# =============================================================================
# Node Tooling Script (coder_script)
# =============================================================================

resource "coder_script" "node_tooling" {
  count = local.has_packages ? 1 : 0

  agent_id           = var.agent_id
  display_name       = "Node Tooling"
  icon               = "/icon/nodejs.svg"
  run_on_start       = true
  start_blocks_login = false  # Don't block login for optional tooling

  script = <<-EOT
    #!/bin/bash
    set +e  # Don't fail on optional package installs

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[NODE-TOOLING] Installing global packages..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for node-version module to finish (node must be available)
    MAX_WAIT=120
    WAITED=0
    while ! command -v node >/dev/null 2>&1; do
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[NODE-TOOLING] WARNING: Node.js not found after $${MAX_WAIT}s, skipping tooling"
        exit 0
      fi
      sleep 2
      WAITED=$((WAITED + 2))
      # Source NVM if it exists (NVM installs node into a non-standard path)
      if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        \. "$NVM_DIR/nvm.sh"
      fi
    done

    echo "[NODE-TOOLING] Node: $(node -v), npm: $(npm -v 2>/dev/null || echo 'n/a')"

    # ── Configure cache directories ──
    mkdir -p ~/.cache/node ~/.npm ~/.pnpm-store ~/.yarn 2>/dev/null || true

    ensure_profile_line() {
      local LINE="$1"
      grep -qxF "$LINE" ~/.bashrc 2>/dev/null || echo "$LINE" >> ~/.bashrc
    }

    case "${var.package_manager}" in
      pnpm)
        export PNPM_HOME="$HOME/.local/share/pnpm"
        ensure_profile_line 'export PNPM_HOME="$HOME/.local/share/pnpm"'
        ensure_profile_line 'export PATH="$PNPM_HOME:$PATH"'
        export PATH="$PNPM_HOME:$PATH"
        ;;
      yarn)
        export YARN_CACHE_FOLDER="$HOME/.yarn"
        ensure_profile_line 'export YARN_CACHE_FOLDER="$HOME/.yarn"'
        ;;
    esac

    # ── Install function ──
    install_global() {
      local PKG="$1"
      echo "[NODE-TOOLING] Installing: $PKG"
      case "${var.package_manager}" in
        pnpm)
          pnpm add -g "$PKG" 2>/dev/null || npm install -g "$PKG" 2>/dev/null || true
          ;;
        yarn)
          yarn global add "$PKG" 2>/dev/null || npm install -g "$PKG" 2>/dev/null || true
          ;;
        npm|*)
          npm install -g "$PKG" 2>/dev/null || sudo npm install -g "$PKG" 2>/dev/null || true
          ;;
      esac
    }

    # ── Install packages ──
    %{ for pkg in local.packages ~}
    install_global "${pkg}"
    %{ endfor ~}

    echo "[NODE-TOOLING] Installed packages:"
    %{ for pkg in local.packages ~}
    echo "  ${pkg}: $(command -v ${pkg} >/dev/null 2>&1 && echo 'OK' || echo 'not in PATH')"
    %{ endfor ~}

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[NODE-TOOLING] Done"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "packages_installed" {
  description = "List of global packages configured for installation"
  value       = local.packages
}
