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
    # NODE TOOLING START
    # Disable strict error checking to allow logging and recovery
    set +e
    
    LOG_FILE="$HOME/node-tooling.log"
    echo "[NODE-TOOLING] Starting setup at $(date)" > "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
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
    # Check if NVM is installed correctly (nvm.sh must exist)
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
      echo "[NODE-TOOLING] Installing NVM (nvm.sh not found)..." | tee -a "$LOG_FILE"
      rm -rf "$NVM_DIR" # Clean up partial install
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
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        \. "$NVM_DIR/nvm.sh"
    else
        echo "[NODE-TOOLING] ERROR: nvm.sh not found at $NVM_DIR/nvm.sh" | tee -a "$LOG_FILE"
    fi

    echo "[NODE-TOOLING] Installing/Using Node.js version: ${var.node_version}..." | tee -a "$LOG_FILE"
    
    # Debug: Check if nvm is a function
    if ! command -v nvm &> /dev/null; then
         echo "[NODE-TOOLING] ERROR: nvm command not found!" | tee -a "$LOG_FILE"
    else
         echo "[NODE-TOOLING] nvm version: $(nvm --version)" | tee -a "$LOG_FILE"
    fi

    # Run nvm install without redirection to see output in main log
    nvm install "${var.node_version}"
    nvm alias default "${var.node_version}"
    nvm use default

    if ! command -v node &> /dev/null; then
        echo "[NODE-TOOLING] ERROR: Node not found after installation!" | tee -a "$LOG_FILE"
        # Fallback: Try to find where it installed
        echo "[NODE-TOOLING] Debug: NVM_DIR content:" | tee -a "$LOG_FILE"
        ls -R "$NVM_DIR/versions" | head -n 20 | tee -a "$LOG_FILE"
    else
        echo "[NODE-TOOLING] Node installed successfully: $(node -v)" | tee -a "$LOG_FILE"
    fi

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
