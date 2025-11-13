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
# Docker Setup Script (Combined Install + Config)
# =============================================================================
# NOTE: This is ONE script, not split into install/config to avoid join() issues

locals {
  docker_setup_script = <<-EOT
    #!/bin/bash
    
    echo "[DOCKER] Setting up Docker-in-Docker..."
    
    # Check/install Docker
    if ! command -v docker >/dev/null 2>&1; then
      echo "[DOCKER] Installing Docker..."
      curl -fsSL https://get.docker.com | sh
    fi
    echo "[DOCKER] ✓ Docker CLI installed: $(docker --version)"
    
    # Configure daemon
    mkdir -p /home/coder/.config/docker
    echo '{"insecure-registries":["registry-cache:5000"],"registry-mirrors":["http://registry-cache:5000"]}' > /home/coder/.config/docker/daemon.json
    
    # Start daemon
    sudo dockerd --config-file /home/coder/.config/docker/daemon.json > /tmp/dockerd.log 2>&1 &
    sleep 3
    
    # Configure environment
    echo 'export DOCKER_HOST=unix:///var/run/docker.sock' >> ~/.bashrc
    export DOCKER_HOST=unix:///var/run/docker.sock
    
    # Create network
    docker network inspect coder-net >/dev/null 2>&1 || docker network create coder-net
    
    echo "[DOCKER] ✓ Docker-in-Docker ready"
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

output "docker_setup_script" {
  description = "Combined script to install and configure Docker-in-Docker"
  value       = local.docker_setup_script
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
