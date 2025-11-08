terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# MODULE: Node Version Manager
# =============================================================================
# DESCRIPTION:
#   Installs and selects a Node.js version according to the chosen strategy.
#   Strategies: system (no-op), volta, fnm, n
#   Produces a script to be sourced/run during workspace startup.

variable "install_strategy" {
  description = "Node install strategy: system|volta|fnm|n"
  type        = string
  default     = "system"
}

variable "node_version" {
  description = "Desired Node version (e.g., 'lts', '22', '20', '18', '16', 'latest')"
  type        = string
  default     = "lts"
}

variable "package_manager" {
  description = "Preferred package manager: npm|pnpm|yarn (used for enabling corepack)"
  type        = string
  default     = "npm"
}

locals {
  resolved_version = var.node_version == "latest-lts" ? "lts" : var.node_version
}

locals {
  setup_script = <<-EOT
    #!/bin/bash
    set -e
    echo "[NODE] Setup strategy: ${var.install_strategy}, version: ${local.resolved_version}"
    
    ensure_profile_line() {
      local LINE="$1"
      grep -qxF "$LINE" ~/.bashrc || echo "$LINE" >> ~/.bashrc
    }

    case "${var.install_strategy}" in
      system)
        echo "[NODE] Installing Node.js v${local.resolved_version} via NodeSource..."
        if ! command -v node >/dev/null 2>&1; then
          # Convert lts to a specific version number (20 is current LTS)
          VERSION="${local.resolved_version}"
          if [ "$VERSION" = "lts" ]; then
            VERSION="20"
          fi
          curl -fsSL https://deb.nodesource.com/setup_$${VERSION}.x | sudo -E bash -
          sudo apt-get install -y nodejs
          echo "[NODE] ✅ Node version: $(node -v)"
          echo "[NODE] ✅ NPM version: $(npm -v)"
        else
          echo "[NODE] Node already installed: $(node -v)"
        fi
        ;;
      volta)
        if ! command -v volta >/dev/null 2>&1; then
          echo "[NODE] Installing Volta..."
          curl -fsSL https://get.volta.sh | bash -s -- --skip-setup
          ensure_profile_line 'export VOLTA_HOME="$HOME/.volta"'
          ensure_profile_line 'export PATH="$VOLTA_HOME/bin:$PATH"'
          export VOLTA_HOME="$HOME/.volta"
          export PATH="$VOLTA_HOME/bin:$PATH"
        fi
        echo "[NODE] Volta selecting version ${local.resolved_version}"
        volta install node@${local.resolved_version}
        ;;
      fnm)
        if ! command -v fnm >/dev/null 2>&1; then
          echo "[NODE] Installing FNM..."
          curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
          ensure_profile_line 'export FNM_DIR="$HOME/.fnm"'
          ensure_profile_line 'export PATH="$FNM_DIR/bin:$PATH"'
          ensure_profile_line 'eval "$(fnm env --use-on-cd)"'
          export FNM_DIR="$HOME/.fnm"
          export PATH="$FNM_DIR/bin:$PATH"
          eval "$(fnm env --use-on-cd)"
        fi
        echo "[NODE] FNM selecting version ${local.resolved_version}"
        fnm install ${local.resolved_version}
        fnm use ${local.resolved_version}
        ;;
      n)
        if ! command -v n >/dev/null 2>&1; then
          echo "[NODE] Installing n..."
          sudo npm install -g n
        fi
        case "${local.resolved_version}" in
          lts)
            n lts
            ;;
          latest|current)
            n latest
            ;;
          *)
            n ${local.resolved_version}
            ;;
        esac
        ;;
      *)
        echo "[NODE] Unknown install strategy: ${var.install_strategy} (skipping)"
        ;;
    esac

    if command -v corepack >/dev/null 2>&1; then
      echo "[NODE] Enabling corepack"
      corepack enable || true
      # Pre-prepare selected manager to avoid first-run latency
      case "${var.package_manager}" in
        pnpm)
          corepack prepare pnpm@latest --activate || true
          ;;
        yarn)
          corepack prepare yarn@stable --activate || true
          ;;
      esac
    fi

    echo "[NODE] Node: $(node -v 2>/dev/null || echo not installed), npm: $(npm -v 2>/dev/null || echo -)"
    echo "[NODE] Done."
    echo ""
  EOT
}

output "node_setup_script" {
  description = "Script to install/select Node version"
  value       = local.setup_script
}
