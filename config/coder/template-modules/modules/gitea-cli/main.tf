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
    echo "[GITEA-CLI] Installing Gitea CLI (tea)..."
    
    # Download and install tea
    TEA_VERSION="0.9.2"
    wget -q "https://dl.gitea.com/tea/$${TEA_VERSION}/tea-$${TEA_VERSION}-linux-amd64" -O /tmp/tea
    chmod +x /tmp/tea
    sudo mv /tmp/tea /usr/local/bin/tea
    
    # Verify installation
    if tea --version > /dev/null 2>&1; then
      echo "[GITEA-CLI] ✓ Gitea CLI installed: $(tea --version)"
    else
      echo "[GITEA-CLI] ✗ Failed to install Gitea CLI"
      exit 1
    fi
    
    echo "[GITEA-CLI] Installation complete"
  EOT
}
