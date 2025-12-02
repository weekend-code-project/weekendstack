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
    # set -e # Disable strict error checking to allow logging and recovery
    
    LOG_FILE="$HOME/node-tooling.log"
    echo "[NODE-TOOLING] Starting setup at $(date)" > "$LOG_FILE"
    
    echo "[NODE-TOOLING] Checking for curl..." | tee -a "$LOG_FILE"
    if ! command -v curl &> /dev/null; then
        echo "[NODE-TOOLING] Installing curl..." | tee -a "$LOG_FILE"
        sudo apt-get update >> "$LOG_FILE" 2>&1
        sudo apt-get install -y curl >> "$LOG_FILE" 2>&1
    fi

    ensure_profile_line() {
      local LINE="$1"
      grep -qxF "$LINE" ~/.bashrc || echo "$LINE" >> ~/.bashrc
    }

    # Install NVM and Node.js
    export NVM_DIR="$HOME/.nvm"
    if [ ! -d "$NVM_DIR" ]; then
      echo "[NODE-TOOLING] Installing NVM..." | tee -a "$LOG_FILE"
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash >> "$LOG_FILE" 2>&1
    fi

    # Explicitly ensure .bashrc has NVM loading logic
    if ! grep -q "NVM_DIR" ~/.bashrc; then
      echo "[NODE-TOOLING] Adding NVM to .bashrc..." | tee -a "$LOG_FILE"
      echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.bashrc
      echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.bashrc
    fi

    # Load NVM for this script
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    echo "[NODE-TOOLING] Installing/Using Node.js version: ${var.node_version}..." | tee -a "$LOG_FILE"
    nvm install "${var.node_version}" >> "$LOG_FILE" 2>&1
    nvm alias default "${var.node_version}" >> "$LOG_FILE" 2>&1
    nvm use default >> "$LOG_FILE" 2>&1

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
      echo "[NODE-TOOLING] Installing global package: $PKG" | tee -a "$LOG_FILE"
      case "${var.package_manager}" in
        pnpm)
          pnpm add -g "$PKG" >> "$LOG_FILE" 2>&1 || sudo pnpm add -g "$PKG" >> "$LOG_FILE" 2>&1 || true
          ;;
        yarn)
          yarn global add "$PKG" >> "$LOG_FILE" 2>&1 || sudo yarn global add "$PKG" >> "$LOG_FILE" 2>&1 || true
          ;;
        npm|*)
          npm install -g "$PKG" >> "$LOG_FILE" 2>&1 || sudo npm install -g "$PKG" >> "$LOG_FILE" 2>&1 || true
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
