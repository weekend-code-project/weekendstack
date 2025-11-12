# =============================================================================
# MODULE: Docker Integration
# =============================================================================
# DESCRIPTION:
#   Provides Docker-in-Docker setup scripts for Coder workspaces.
#   Install Docker Engine and configure daemon for registry mirrors.
#
# OUTPUTS:
#   - docker_install_script: Script to install Docker
#   - docker_config_script: Script to configure Docker daemon
#
# =============================================================================

# =============================================================================
# Docker Install Script
# =============================================================================

locals {
  docker_install_script = <<-EOT
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
    
    echo ""
  EOT
}

# =============================================================================
# Docker Config Script
# =============================================================================

locals {
  docker_config_script = <<-EOT
    #!/bin/bash
    
    echo "[DOCKER-CONFIG] Configuring Docker-in-Docker daemon..."
    echo "[DOCKER-CONFIG] DEBUG: Step 1 - Starting config"
    
    # Check if dockerd is already running
    if pgrep dockerd >/dev/null 2>&1; then
      echo "[DOCKER-CONFIG] ✓ Docker daemon already running (PID: $(pgrep dockerd))"
      echo "[DOCKER-CONFIG] ✓ Docker-in-Docker already configured"
      exit 0
    fi
    
    echo "[DOCKER-CONFIG] DEBUG: Step 2 - dockerd not running, need to start it"
    
    # Create Docker config directory
    mkdir -p /home/coder/.config/docker 2>/dev/null || true
    echo "[DOCKER-CONFIG] DEBUG: Step 3 - Created config directory"
    
    # Write daemon configuration
    cat > /home/coder/.config/docker/daemon.json 2>/dev/null <<'JSON'
{
  "insecure-registries": ["registry-cache:5000"],
  "registry-mirrors": ["http://registry-cache:5000"]
}
JSON
    echo "[DOCKER-CONFIG] DEBUG: Step 4 - Wrote daemon config"
    
    # Export for current session
    export DOCKER_HOST=unix:///var/run/docker.sock
    echo "[DOCKER-CONFIG] DEBUG: Step 5 - Set DOCKER_HOST"
    
    # Start Docker daemon
    echo "[DOCKER-CONFIG] Starting Docker daemon..."
    sudo dockerd --config-file /home/coder/.config/docker/daemon.json >/tmp/dockerd.log 2>&1 &
    echo "[DOCKER-CONFIG] DEBUG: Step 6 - Started dockerd in background"
    
    # Wait for Docker daemon (quick check)
    sleep 2
    if docker info >/dev/null 2>&1; then
      echo "[DOCKER-CONFIG] ✓ Docker daemon is ready"
    else
      echo "[DOCKER-CONFIG] ⚠ Docker daemon may not be ready - check logs: tail /tmp/dockerd.log"
    fi
    
    echo "[DOCKER-CONFIG] ✓ Docker-in-Docker setup complete"
    echo ""
  EOT
}

# =============================================================================
# Docker Validation/Test Script
# =============================================================================

locals {
  docker_test_script = <<-EOT
    #!/bin/bash
    set -e
    
    echo "[DOCKER-TEST] Running minimal Docker validation..."
    
    # Test 1: Docker CLI exists
    if docker --version >/dev/null 2>&1; then
      echo "[DOCKER-TEST] PASS - Docker CLI: $(docker --version)"
    else
      echo "[DOCKER-TEST] FAIL - Docker CLI not found"
      exit 1
    fi
    
    # Test 2: Docker daemon responding
    if docker ps >/dev/null 2>&1; then
      CONTAINER_COUNT=$(docker ps -q | wc -l)
      echo "[DOCKER-TEST] PASS - Docker daemon responding ($${CONTAINER_COUNT} containers running)"
    else
      echo "[DOCKER-TEST] FAIL - Docker daemon not responding"
      exit 1
    fi
    
    echo "[DOCKER-TEST] Validation complete - Docker is functional"
    echo ""
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "docker_install_script" {
  description = "Script to install Docker"
  value       = local.docker_install_script
}

output "docker_config_script" {
  description = "Script to configure Docker daemon"
  value       = local.docker_config_script
}

output "docker_test_script" {
  description = "Script to validate Docker installation"
  value       = local.docker_test_script
}

output "metadata_blocks" {
  description = "Metadata blocks contributed by this module"
  value = [
    {
      display_name = "Docker Status"
      script       = "docker info --format '{{.ServerVersion}} ({{.Containers}} containers)' 2>/dev/null || echo 'Not running'"
      interval     = 30
      timeout      = 2
    }
  ]
}
