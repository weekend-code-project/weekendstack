# =============================================================================
# MODULE: Docker Configuration
# =============================================================================
# DESCRIPTION:
#   Configures and starts a Docker-in-Docker (DinD) daemon inside the workspace.
#   This provides complete Docker isolation - each workspace gets its own Docker
#   daemon with its own containers, networks, and volumes.
#
# ARCHITECTURE:
#   - True Docker-in-Docker (NOT socket forwarding)
#   - Requires privileged container (privileged = true)
#   - Runs dockerd as root inside workspace container
#   - Each workspace has isolated Docker environment
#   - No access to host Docker or other workspaces' containers
#
# DEPENDENCIES:
#   - install-docker module (Docker must be installed first)
#   - data.coder_parameter.workspace_secret (for registry authentication)
#   - Container must have privileged = true
#
# CONFIGURATION:
#   - Insecure registries: registry-cache:5000
#   - Registry mirrors: http://registry-cache:5000
#   - Network: coder-net (auto-created)
#   - Socket: unix:///var/run/docker.sock (workspace-local)
#
# ENVIRONMENT VARIABLES:
#   - DOCKER_HOST: Set to unix:///var/run/docker.sock (workspace socket)
#   - Requires random_password.workspace_secret.result
#
# USAGE:
#   # In main.tf, ensure privileged container:
#   resource "docker_container" "workspace" {
#     privileged = true  # Required for DinD!
#   }
#
#   # In startup script:
#   startup_script = join("\n", [
#     local.install_docker,  # Must run first
#     local.docker_config,   # Then configure
#   ])
#
# OUTPUTS:
#   - local.docker_config (string): Bash script segment
#
# NOTES:
#   - macOS users: Expect performance overhead due to nested virtualization
#   - Each workspace daemon is completely isolated
#   - docker ps only shows workspace containers (not host)
#   - Full docker compose support with networks and volumes
#
# =============================================================================

locals {
  docker_config = <<-EOT
    #!/bin/bash
    set -e
    
    echo "[DOCKER-CONFIG] Configuring Docker-in-Docker daemon..."
    
    # Create Docker config directory
    mkdir -p /home/coder/.config/docker
    
    # Write daemon configuration
    cat > /home/coder/.config/docker/daemon.json <<'JSON'
{
  "insecure-registries": ["registry-cache:5000"],
  "registry-mirrors": ["http://registry-cache:5000"]
}
JSON
    echo "[DOCKER-CONFIG] ✓ Daemon config created"
    
    # Configure Docker host socket in bash profile
    if ! grep -q "DOCKER_HOST=unix:///var/run/docker.sock" ~/.bashrc; then
      echo 'export DOCKER_HOST=unix:///var/run/docker.sock' >> ~/.bashrc
      echo "[DOCKER-CONFIG] ✓ DOCKER_HOST configured in .bashrc"
    fi
    
    # Export for current session
    export DOCKER_HOST=unix:///var/run/docker.sock
    
    # Start Docker daemon in background if not already running
    if ! pgrep dockerd >/dev/null 2>&1; then
      echo "[DOCKER-CONFIG] Starting Docker daemon..."
      sudo dockerd --config-file /home/coder/.config/docker/daemon.json > /tmp/dockerd.log 2>&1 &
      
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
      echo "[DOCKER-CONFIG] Docker daemon already running"
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
