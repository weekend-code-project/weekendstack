# =============================================================================
# MODULE: Install Docker
# =============================================================================
# DESCRIPTION:
#   Installs Docker Engine in the workspace if not already present.
#   Uses the official Docker installation script for Ubuntu/Debian.
#
# DEPENDENCIES:
#   - None (foundation module)
#
# IDEMPOTENCY:
#   Checks if docker command exists before attempting installation
#
# OUTPUTS:
#   - local.install_docker (string): Bash script segment
#
# NOTES:
#   - Silent installation (no version output on skip)
#   - Uses official get.docker.com installation script
#   - Part of Docker-in-Docker setup (requires docker-config module)
#
# =============================================================================

locals {
  install_docker = <<-EOT
    #!/bin/bash
    set -e
    
    echo "[DOCKER-INSTALL] Checking Docker installation..."
    
    if ! command -v docker >/dev/null 2>&1; then
      echo "[DOCKER-INSTALL] Installing Docker..."
      curl -fsSL https://get.docker.com | sh
      echo "[DOCKER-INSTALL] ✓ Docker installed: $(docker --version)"
    else
      echo "[DOCKER-INSTALL] ✓ Docker already installed: $(docker --version)"
    fi
  EOT
}
