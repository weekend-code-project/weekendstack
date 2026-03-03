# =============================================================================
# MODULE: Node Version Manager
# =============================================================================
# Installs and selects a Node.js version using a configurable strategy.
#
# Strategies:
#   - system:  Install from NodeSource apt repo (fast, no version manager)
#   - nvm:     Install NVM + requested version (most compatible, default)
#   - volta:   Install Volta + requested version (fast, hermetic)
#   - fnm:     Install FNM + requested version (Rust-based, fast)
#   - n:       Install `n` via npm + requested version
#
# Also enables Corepack for pnpm/yarn package managers when available.
#
# This module creates a `coder_script` that runs at workspace startup.
# It is self-contained and can be used in any template.
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

variable "install_strategy" {
  description = "Node install strategy: system | nvm | volta | fnm | n"
  type        = string
  default     = "nvm"

  validation {
    condition     = contains(["system", "nvm", "volta", "fnm", "n"], var.install_strategy)
    error_message = "install_strategy must be one of: system, nvm, volta, fnm, n"
  }
}

variable "node_version" {
  description = "Desired Node.js version (e.g., 'lts', '22', '20', '18', 'latest')"
  type        = string
  default     = "lts"
}

variable "package_manager" {
  description = "Preferred package manager: npm | pnpm | yarn (used for corepack activation)"
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
  # Normalize version names
  resolved_version = var.node_version == "latest-lts" ? "lts" : var.node_version
}

# =============================================================================
# Node Setup Script (coder_script)
# =============================================================================

resource "coder_script" "node_version" {
  agent_id           = var.agent_id
  display_name       = "Node.js Setup"
  icon               = "/icon/nodejs.svg"
  run_on_start       = true
  start_blocks_login = true  # Block login until Node is ready

  script = <<-EOT
    #!/bin/bash
    set -e

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[NODE] Installing Node.js (strategy: ${var.install_strategy}, version: ${local.resolved_version})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    ensure_profile_line() {
      local LINE="$1"
      grep -qxF "$LINE" ~/.bashrc 2>/dev/null || echo "$LINE" >> ~/.bashrc
    }

    # ── Install curl if missing ──
    if ! command -v curl >/dev/null 2>&1; then
      echo "[NODE] Installing curl..."
      (
        flock -w 300 9 || { echo "[NODE] WARNING: Could not acquire apt lock"; exit 1; }
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y -qq curl >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
    fi

    case "${var.install_strategy}" in

      # ─────────────────────────────────────────────────────────────
      # System: NodeSource apt repo (no version manager)
      # ─────────────────────────────────────────────────────────────
      system)
        if command -v node >/dev/null 2>&1; then
          echo "[NODE] Node already installed: $(node -v)"
        else
          VERSION="${local.resolved_version}"
          if [ "$VERSION" = "lts" ]; then
            VERSION="20"
          fi
          echo "[NODE] Installing Node.js v$VERSION via NodeSource..."
          (
            flock -w 300 9 || { echo "[NODE] WARNING: Could not acquire apt lock"; exit 1; }
            curl -fsSL "https://deb.nodesource.com/setup_$${VERSION}.x" | sudo -E bash - >/dev/null 2>&1
            sudo apt-get install -y -qq nodejs >/dev/null 2>&1
          ) 9>/tmp/coder-apt.lock
        fi
        ;;

      # ─────────────────────────────────────────────────────────────
      # NVM (Node Version Manager)
      # ─────────────────────────────────────────────────────────────
      nvm)
        export NVM_DIR="$HOME/.nvm"

        if [ ! -s "$NVM_DIR/nvm.sh" ]; then
          echo "[NODE] Installing NVM..."
          rm -rf "$NVM_DIR"
          curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1
        fi

        # Ensure .bashrc loads NVM
        if ! grep -q "NVM_DIR" ~/.bashrc 2>/dev/null; then
          echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
          echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
          echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
        fi

        # Load NVM for this script
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        if [ "${local.resolved_version}" = "lts" ]; then
          nvm install --lts >/dev/null 2>&1
          nvm alias default 'lts/*' >/dev/null 2>&1
          nvm use default >/dev/null 2>&1
        else
          nvm install "${local.resolved_version}" >/dev/null 2>&1
          nvm alias default "${local.resolved_version}" >/dev/null 2>&1
          nvm use default >/dev/null 2>&1
        fi
        ;;

      # ─────────────────────────────────────────────────────────────
      # Volta
      # ─────────────────────────────────────────────────────────────
      volta)
        if ! command -v volta >/dev/null 2>&1; then
          echo "[NODE] Installing Volta..."
          curl -fsSL https://get.volta.sh | bash -s -- --skip-setup >/dev/null 2>&1
          ensure_profile_line 'export VOLTA_HOME="$HOME/.volta"'
          ensure_profile_line 'export PATH="$VOLTA_HOME/bin:$PATH"'
          export VOLTA_HOME="$HOME/.volta"
          export PATH="$VOLTA_HOME/bin:$PATH"
        fi
        echo "[NODE] Volta installing node@${local.resolved_version}..."
        volta install "node@${local.resolved_version}" >/dev/null 2>&1
        ;;

      # ─────────────────────────────────────────────────────────────
      # FNM (Fast Node Manager)
      # ─────────────────────────────────────────────────────────────
      fnm)
        if ! command -v fnm >/dev/null 2>&1; then
          echo "[NODE] Installing FNM..."
          curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell >/dev/null 2>&1
          ensure_profile_line 'export FNM_DIR="$HOME/.fnm"'
          ensure_profile_line 'export PATH="$FNM_DIR:$PATH"'
          ensure_profile_line 'eval "$(fnm env --use-on-cd)"'
          export FNM_DIR="$HOME/.fnm"
          export PATH="$FNM_DIR:$PATH"
          eval "$(fnm env --use-on-cd)"
        fi
        echo "[NODE] FNM installing ${local.resolved_version}..."
        fnm install "${local.resolved_version}" >/dev/null 2>&1
        fnm use "${local.resolved_version}" >/dev/null 2>&1
        ;;

      # ─────────────────────────────────────────────────────────────
      # n (simple Node version manager)
      # ─────────────────────────────────────────────────────────────
      n)
        if ! command -v n >/dev/null 2>&1; then
          echo "[NODE] Installing n..."
          # Need npm first to install n
          if ! command -v npm >/dev/null 2>&1; then
            (
              flock -w 300 9 || true
              curl -fsSL "https://deb.nodesource.com/setup_20.x" | sudo -E bash - >/dev/null 2>&1
              sudo apt-get install -y -qq nodejs >/dev/null 2>&1
            ) 9>/tmp/coder-apt.lock
          fi
          sudo npm install -g n >/dev/null 2>&1
        fi
        case "${local.resolved_version}" in
          lts)     sudo n lts >/dev/null 2>&1 ;;
          latest)  sudo n latest >/dev/null 2>&1 ;;
          *)       sudo n "${local.resolved_version}" >/dev/null 2>&1 ;;
        esac
        ;;

    esac

    # ── Enable Corepack for pnpm/yarn ──
    if command -v corepack >/dev/null 2>&1; then
      echo "[NODE] Enabling Corepack..."
      sudo corepack enable 2>/dev/null || corepack enable 2>/dev/null || true
      case "${var.package_manager}" in
        pnpm) corepack prepare pnpm@latest --activate 2>/dev/null || true ;;
        yarn) corepack prepare yarn@stable --activate 2>/dev/null || true ;;
      esac
    fi

    # ── Verify installation ──
    if command -v node >/dev/null 2>&1; then
      echo "[NODE] Node: $(node -v)"
      echo "[NODE] npm:  $(npm -v 2>/dev/null || echo 'not found')"
      case "${var.package_manager}" in
        pnpm) echo "[NODE] pnpm: $(pnpm -v 2>/dev/null || echo 'not installed')" ;;
        yarn) echo "[NODE] yarn: $(yarn -v 2>/dev/null || echo 'not installed')" ;;
      esac
    else
      echo "[NODE] WARNING: Node.js not found after installation"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[NODE] Done"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "install_strategy" {
  description = "The strategy used to install Node.js"
  value       = var.install_strategy
}

output "node_version" {
  description = "The requested Node.js version"
  value       = local.resolved_version
}

output "package_manager" {
  description = "The configured package manager"
  value       = var.package_manager
}
