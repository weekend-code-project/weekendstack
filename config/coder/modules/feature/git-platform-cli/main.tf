# =============================================================================
# MODULE: Git Platform CLI Installer
# =============================================================================
# Installs the appropriate Git platform CLI tool based on user selection:
#
#   "none"   → no script created (count = 0)
#   "github" → installs `gh` (GitHub CLI) via official apt repo
#   "gitlab" → installs `glab` (GitLab CLI) via packages.gitlab.com.
#              If gitlab_host is set, exports GITLAB_HOST in ~/.bashrc so
#              glab targets your self-hosted instance automatically.
#   "gitea"  → downloads `tea` v0.9.2 binary from dl.gitea.com.
#              Works with any self-hosted Gitea at login time (no extra config).
#
# Platform detection by URL is intentionally NOT implemented: self-hosted
# Gitea and GitLab are indistinguishable by URL pattern alone.
# The user selects their platform explicitly when creating the workspace.
#
# CLI tools enable things like creating issues, PRs/MRs, and managing repos
# from inside the workspace \u2014 beyond what git itself provides.
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

variable "git_cli" {
  description = "Which Git platform CLI to install. 'none' skips installation."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "github", "gitlab", "gitea"], var.git_cli)
    error_message = "git_cli must be one of: none, github, gitlab, gitea"
  }
}

variable "gitlab_host" {
  description = "Self-hosted GitLab hostname (e.g. git.example.com). Only used when git_cli = 'gitlab'. Leave empty for gitlab.com."
  type        = string
  default     = ""
}

# =============================================================================
# CLI Install Script
# =============================================================================

resource "coder_script" "git_platform_cli" {
  count = var.git_cli != "none" ? 1 : 0

  agent_id           = var.agent_id
  display_name       = "Git Platform CLI"
  icon               = "/icon/git.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-EOT
    #!/bin/bash
    set -e

    GIT_CLI="${var.git_cli}"
    GITLAB_HOST="${var.gitlab_host}"

    echo "====================================================================="
    echo "[GIT-CLI] Installing $GIT_CLI CLI..."
    echo "====================================================================="

    # Serialize apt operations with other parallel startup scripts
    # Must match the lock file used by wordpress install script and ssh-server module
    APT_LOCK="/tmp/coder-apt.lock"

    case "$GIT_CLI" in

      # -----------------------------------------------------------------------
      # GitHub CLI (gh)
      # -----------------------------------------------------------------------
      github)
        echo "[GIT-CLI] Installing gh (GitHub CLI)..."
        (
          flock -w 300 9 || { echo "[GIT-CLI] ERROR: Could not acquire apt lock after 5 min"; exit 1; }

          # Add GitHub's official apt repository
          if [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
            echo "[GIT-CLI] Adding GitHub CLI apt repository..."
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
              | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
              | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt-get update -qq
          fi

          sudo apt-get install -y -qq gh
        ) 9>"$APT_LOCK"

        echo "[GIT-CLI] gh installed: $(gh --version | head -1)"
        echo "[GIT-CLI] Note: 'gh auth login' not needed for clone \u2014 Coder's git SSH auth handles that."
        echo "[GIT-CLI] Use 'gh auth login' manually if you need gh issue/PR commands."
        ;;

      # -----------------------------------------------------------------------
      # GitLab CLI (glab)
      # -----------------------------------------------------------------------
      gitlab)
        echo "[GIT-CLI] Installing glab (GitLab CLI)..."
        (
          flock -w 300 9 || { echo "[GIT-CLI] ERROR: Could not acquire apt lock after 5 min"; exit 1; }

          if [ ! -f /etc/apt/sources.list.d/gitlab-org-cli.list ]; then
            echo "[GIT-CLI] Adding GitLab CLI apt repository..."
            curl -fsSL https://packages.gitlab.com/gitlab-org/cli/gpgkey \
              | sudo gpg --dearmor -o /usr/share/keyrings/gitlab-org-cli-keyring.gpg 2>/dev/null
            echo "deb [signed-by=/usr/share/keyrings/gitlab-org-cli-keyring.gpg] https://packages.gitlab.com/gitlab-org/cli/ubuntu/ $(lsb_release -cs 2>/dev/null || echo focal) main" \
              | sudo tee /etc/apt/sources.list.d/gitlab-org-cli.list > /dev/null
            sudo apt-get update -qq
          fi

          sudo apt-get install -y -qq glab
        ) 9>"$APT_LOCK"

        echo "[GIT-CLI] glab installed: $(glab --version | head -1)"

        # Point glab at self-hosted instance if configured
        if [ -n "$GITLAB_HOST" ]; then
          echo "[GIT-CLI] Configuring glab for self-hosted GitLab: $GITLAB_HOST"
          if ! grep -q "GITLAB_HOST" "$HOME/.bashrc" 2>/dev/null; then
            echo "" >> "$HOME/.bashrc"
            echo "# GitLab CLI \u2014 self-hosted instance" >> "$HOME/.bashrc"
            echo "export GITLAB_HOST=$GITLAB_HOST" >> "$HOME/.bashrc"
          fi
          export GITLAB_HOST="$GITLAB_HOST"
          echo "[GIT-CLI] GITLAB_HOST set to: $GITLAB_HOST"
        else
          echo "[GIT-CLI] Using gitlab.com (no GITLAB_HOST set)"
        fi
        echo "[GIT-CLI] Use 'glab auth login' to authenticate for issue/MR commands."
        ;;

      # -----------------------------------------------------------------------
      # Gitea CLI (tea)
      # -----------------------------------------------------------------------
      gitea)
        echo "[GIT-CLI] Installing tea (Gitea CLI)..."
        TEA_VERSION="0.9.2"
        ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

        # Map dpkg arch to Gitea release arch names
        case "$ARCH" in
          amd64)   TEA_ARCH="amd64" ;;
          arm64)   TEA_ARCH="arm64" ;;
          armhf)   TEA_ARCH="arm-6" ;;
          *)       TEA_ARCH="amd64" ;;
        esac

        TEA_URL="https://dl.gitea.com/tea/$${TEA_VERSION}/tea-$${TEA_VERSION}-linux-$${TEA_ARCH}"
        TEA_BIN="/usr/local/bin/tea"

        echo "[GIT-CLI] Downloading tea v$TEA_VERSION ($TEA_ARCH) from $TEA_URL"
        sudo curl -fsSL -o "$TEA_BIN" "$TEA_URL"
        sudo chmod +x "$TEA_BIN"

        echo "[GIT-CLI] tea installed: $(tea --version 2>/dev/null || echo 'v'$TEA_VERSION)"
        echo "[GIT-CLI] Use 'tea login add' to authenticate for issue commands."
        ;;

    esac

    echo "====================================================================="
    echo "[GIT-CLI] Done"
    echo "====================================================================="
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "platform" {
  description = "The selected git CLI platform (none/github/gitlab/gitea)"
  value       = var.git_cli
}
