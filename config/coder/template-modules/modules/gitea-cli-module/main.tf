# =============================================================================
# MODULE: Gitea CLI (tea)
# =============================================================================
# DESCRIPTION:
#   Installs the Gitea CLI tool (tea) for Gitea repository operations.
#
# OUTPUTS:
#   - install_script: Shell script to install Gitea CLI
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.0.0"
    }
  }
}

# Gitea CLI Installation Script
output "install_script" {
  description = "Script to install Gitea CLI (tea)"
  value       = <<-EOT
    if command -v tea >/dev/null 2>&1; then
      echo "[GITEA-CLI] ✓ Already installed"
    else
      echo "[GITEA-CLI] Installing..."
      TEA_VERSION="0.9.2"
      wget -q "https://dl.gitea.com/tea/$${TEA_VERSION}/tea-$${TEA_VERSION}-linux-amd64" -O /tmp/tea 2>/dev/null
      chmod +x /tmp/tea
      sudo mv /tmp/tea /usr/local/bin/tea
      
      if command -v tea >/dev/null 2>&1; then
        echo "[GITEA-CLI] ✓ Installed"
      else
        echo "[GITEA-CLI] ✗ Installation failed"
      fi
    fi
    
    echo ""  # Line break after module
  EOT
}
