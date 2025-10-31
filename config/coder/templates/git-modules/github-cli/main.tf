# =============================================================================
# MODULE: GitHub CLI
# =============================================================================
# DESCRIPTION:
#   Installs the GitHub CLI (gh) tool in the workspace.
#   Provides command-line access to GitHub features.
#
# USAGE:
#   This module outputs a shell script that should be included in the
#   coder_agent startup_script.
#
# OUTPUTS:
#   - install_script: Shell script to install GitHub CLI
# =============================================================================

output "install_script" {
  description = "Shell script to install GitHub CLI"
  value       = <<-EOT
    #!/bin/bash
    set -e
    
    if command -v gh >/dev/null 2>&1; then
      echo "[GITHUB-CLI] Already installed ($(gh --version | head -n1))"
    else
      echo "[GITHUB-CLI] Installing GitHub CLI..."
      
      # Add GitHub CLI repository
      (
        type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
      ) >/dev/null 2>&1
      
      if command -v gh >/dev/null 2>&1; then
        echo "[GITHUB-CLI] ✅ Installed successfully ($(gh --version | head -n1))"
      else
        echo "[GITHUB-CLI] ⚠️  Installation failed"
      fi
    fi
  EOT
}
