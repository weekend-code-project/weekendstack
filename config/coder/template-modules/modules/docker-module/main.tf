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
    mkdir -p /home/coder/.config/docker
    echo '{"insecure-registries":["registry-cache:5000"],"registry-mirrors":["http://registry-cache:5000"]}' > /home/coder/.config/docker/daemon.json
    sudo dockerd --config-file /home/coder/.config/docker/daemon.json > /tmp/dockerd.log 2>&1 &
    sleep 3
    echo 'export DOCKER_HOST=unix:///var/run/docker.sock' >> ~/.bashrc
    export DOCKER_HOST=unix:///var/run/docker.sock
    docker network inspect coder-net >/dev/null 2>&1 || docker network create coder-net
    echo "[DOCKER-CONFIG] ✓ Docker-in-Docker configured"
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
