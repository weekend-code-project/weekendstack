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
    
    # Check if Docker is already working (simpler than pgrep which can hang)
    echo "[DOCKER-CONFIG] DEBUG: Step 2 - Checking if Docker already works..."
    if timeout 2 docker info >/dev/null 2>&1; then
      echo "[DOCKER-CONFIG] ✓ Docker is already working"
      echo "[DOCKER-CONFIG] ✓ Docker-in-Docker already configured"
      exit 0
    fi
    
    echo "[DOCKER-CONFIG] DEBUG: Step 3 - Docker not responding, need to configure"
    
    # Create Docker config directory
    echo "[DOCKER-CONFIG] DEBUG: Step 4 - Creating config directory..."
    mkdir -p /home/coder/.config/docker
    echo "[DOCKER-CONFIG] DEBUG: Step 5 - Config directory created"
    
    # Write daemon configuration using echo instead of heredoc to avoid potential hang
    echo "[DOCKER-CONFIG] DEBUG: Step 6 - Writing daemon config..."
    echo '{"insecure-registries":["registry-cache:5000"],"registry-mirrors":["http://registry-cache:5000"]}' > /home/coder/.config/docker/daemon.json
    echo "[DOCKER-CONFIG] DEBUG: Step 7 - Daemon config written"
    
    # Export for current session
    export DOCKER_HOST=unix:///var/run/docker.sock
    echo "[DOCKER-CONFIG] DEBUG: Step 8 - DOCKER_HOST set"
    
    # Start Docker daemon
    echo "[DOCKER-CONFIG] DEBUG: Step 9 - Starting dockerd..."
    sudo dockerd --config-file /home/coder/.config/docker/daemon.json >/tmp/dockerd.log 2>&1 &
    echo "[DOCKER-CONFIG] DEBUG: Step 10 - dockerd started in background"
    
    # Wait for Docker daemon (quick check)
    echo "[DOCKER-CONFIG] DEBUG: Step 11 - Waiting for Docker to be ready..."
    sleep 2
    if timeout 2 docker info >/dev/null 2>&1; then
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
