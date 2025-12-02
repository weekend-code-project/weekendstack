terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# MODULE: Node Tooling Bootstrap
# =============================================================================
# DESCRIPTION:
#   Installs optional global tooling: TypeScript compiler and ESLint.
#   Sets up cache directories for npm/pnpm/yarn to improve performance.

variable "enable_typescript" {
  type        = bool
  default     = true
  description = "Install TypeScript globally"
}

variable "enable_eslint" {
  type        = bool
  default     = true
  description = "Install ESLint globally"
}

variable "enable_http_server" {
  type        = bool
  default     = true
  description = "Install http-server globally"
}

variable "package_manager" {
  type        = string
  default     = "npm"
  description = "npm|pnpm|yarn"
}

variable "node_version" {
  type        = string
  default     = "20"
  description = "Node.js version to install/use"
}

locals {
  tooling_script = <<-EOT
    #!/bin/bash
    set -e
    echo "[NODE-TOOLING] Setting up tooling (pm=${var.package_manager})..."

    ensure_profile_line() {
      local LINE="$1"
      grep -qxF "$LINE" ~/.bashrc || echo "$LINE" >> ~/.bashrc
    }

    # Install NVM and Node.js
    export NVM_DIR="$HOME/.nvm"
    if [ ! -d "$NVM_DIR" ]; then
      echo "[NODE-TOOLING] Installing NVM..."
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    else
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi

    echo "[NODE-TOOLING] Installing/Using Node.js version: ${var.node_version}..."
    nvm install "${var.node_version}"
    nvm alias default "${var.node_version}"
    nvm use default

    # Cache dirs
    mkdir -p ~/.cache/node ~/.npm ~/.pnpm-store ~/.yarn
    case "${var.package_manager}" in
      npm)
        echo "cache=~/.npm" > ~/.npmrc
        ;;
      pnpm)
        export PNPM_HOME="$HOME/.local/share/pnpm"
        ensure_profile_line 'export PNPM_HOME="$HOME/.local/share/pnpm"'
        ensure_profile_line 'export PATH="$PNPM_HOME:$PATH"'
        ;;
      yarn)
        export YARN_CACHE_FOLDER="$HOME/.yarn" || true
        ensure_profile_line 'export YARN_CACHE_FOLDER="$HOME/.yarn"'
        ;;
    esac

    # Install globals using chosen manager (fallback to npm)
    install_global() {
      local PKG="$1"
      case "${var.package_manager}" in
        pnpm)
          pnpm add -g "$PKG" || sudo pnpm add -g "$PKG" || true
          ;;
        yarn)
          yarn global add "$PKG" || sudo yarn global add "$PKG" || true
          ;;
        npm|*)
          npm install -g "$PKG" || sudo npm install -g "$PKG" || true
          ;;
      esac
    }

    if [ "${var.enable_typescript}" = "true" ]; then
      echo "[NODE-TOOLING] Installing TypeScript..."
      install_global typescript
    fi
    if [ "${var.enable_eslint}" = "true" ]; then
      echo "[NODE-TOOLING] Installing ESLint..."
      install_global eslint
    fi
    if [ "${var.enable_http_server}" = "true" ]; then
      echo "[NODE-TOOLING] Installing http-server..."
      install_global http-server
    fi

    echo "[NODE-TOOLING] Node: $(node -v 2>/dev/null || echo -), npm: $(npm -v 2>/dev/null || echo -)"
    echo "[NODE-TOOLING] Done."
    echo ""
  EOT
}

output "tooling_install_script" {
  description = "Script to install global Node tooling"
  value       = local.tooling_script
}
