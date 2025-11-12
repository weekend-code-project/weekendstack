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
    # Note: No set -e here because this script is wrapped in a subshell with || true
    # We want to continue even if some commands fail
    
    echo "[DOCKER-CONFIG] Configuring Docker-in-Docker daemon..."
    
    # Create Docker config directory
    mkdir -p /home/coder/.config/docker || true
    echo "[DOCKER-CONFIG] DEBUG: Created config directory"
    echo "[DOCKER-CONFIG] DEBUG: Created config directory"
    
    # Write daemon configuration
    cat > /home/coder/.config/docker/daemon.json <<'JSON'
{
  "insecure-registries": ["registry-cache:5000"],
  "registry-mirrors": ["http://registry-cache:5000"]
}
JSON
    echo "[DOCKER-CONFIG] ✓ Daemon config created"
    echo "[DOCKER-CONFIG] DEBUG: Daemon config file written"
    
    # Configure Docker host socket in bash profile
    if ! grep -q "DOCKER_HOST=unix:///var/run/docker.sock" ~/.bashrc; then
      echo 'export DOCKER_HOST=unix:///var/run/docker.sock' >> ~/.bashrc
      echo "[DOCKER-CONFIG] ✓ DOCKER_HOST configured in .bashrc"
    fi
    
    # Export for current session
    export DOCKER_HOST=unix:///var/run/docker.sock
    
    # Start Docker daemon in background if not already running
    echo "[DOCKER-CONFIG] Checking if dockerd is running..."
    if ! pgrep dockerd >/dev/null 2>&1; then
      echo "[DOCKER-CONFIG] Starting Docker daemon..."
      # Use nohup and setsid to fully detach dockerd from the shell
      sudo setsid dockerd --config-file /home/coder/.config/docker/daemon.json >/tmp/dockerd.log 2>&1 &
      DOCKERD_PID=$!
      echo "[DOCKER-CONFIG] Started dockerd in background (PID: $DOCKERD_PID)"
      
      # Wait for Docker daemon to be ready (with timeout)
      echo "[DOCKER-CONFIG] Waiting for Docker daemon to be ready..."
      for i in {1..15}; do
        if docker info >/dev/null 2>&1; then
          echo "[DOCKER-CONFIG] ✓ Docker daemon is ready (took $i seconds)"
          break
        fi
        if [ $i -eq 15 ]; then
          echo "[DOCKER-CONFIG] ✗ Docker daemon failed to start after 15 seconds"
          echo "[DOCKER-CONFIG] Check logs: sudo tail -20 /tmp/dockerd.log"
          sudo tail -20 /tmp/dockerd.log || true
          echo "[DOCKER-CONFIG] ⚠ Continuing without Docker-in-Docker..."
          echo ""
          exit 0  # Don't fail workspace, just skip Docker setup
        fi
        sleep 1
      done
    else
      echo "[DOCKER-CONFIG] Docker daemon already running (PID: $(pgrep dockerd))"
      # Still verify it's responding
      if ! docker info >/dev/null 2>&1; then
        echo "[DOCKER-CONFIG] ⚠ Warning: dockerd process exists but not responding"
        echo "[DOCKER-CONFIG] Continuing without Docker-in-Docker..."
        exit 0
      fi
    fi
    
    # Create isolated coder-net network for workspace containers
    echo "[DOCKER-CONFIG] Creating coder-net network..."
    if ! docker network inspect coder-net >/dev/null 2>&1; then
      docker network create coder-net
      echo "[DOCKER-CONFIG] ✓ Created coder-net network"
    else
      echo "[DOCKER-CONFIG] ✓ coder-net network already exists"
    fi
    
    # Verify Docker is working
    if docker ps >/dev/null 2>&1; then
      echo "[DOCKER-CONFIG] ✓ Docker-in-Docker setup complete and verified"
    else
      echo "[DOCKER-CONFIG] ✗ Error: Docker daemon not responding to commands"
      exit 1
    fi
    
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
