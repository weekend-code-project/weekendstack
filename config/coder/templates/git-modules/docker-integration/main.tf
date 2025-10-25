# =============================================================================
# MODULE: Docker Integration
# =============================================================================
# DESCRIPTION:
#   Complete Docker-in-Docker setup for Coder workspaces. Installs Docker Engine,
#   configures daemon, and manages workspace container resources.
#
# ARCHITECTURE:
#   - True Docker-in-Docker (NOT socket forwarding)
#   - Each workspace gets isolated Docker daemon
#   - Requires privileged container
#   - Persistent home volume via Docker volume
#
# DEPENDENCIES:
#   - data.coder_workspace (workspace info)
#   - data.coder_workspace_owner (owner info)
#   - coder_agent (agent configuration)
#   - Traefik labels module (for routing)
#
# OUTPUTS:
#   - docker_install_script: Script to install Docker
#   - docker_config_script: Script to configure Docker daemon
#   - docker_volume: Home volume resource
#   - docker_container: Workspace container resource
#
# =============================================================================

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "workspace_id" {
  description = "Workspace UUID"
  type        = string
}

variable "workspace_name" {
  description = "Workspace name"
  type        = string
}

variable "workspace_owner_name" {
  description = "Workspace owner username"
  type        = string
}

variable "workspace_owner_id" {
  description = "Workspace owner UUID"
  type        = string
}

variable "workspace_start_count" {
  description = "Number of times workspace has started"
  type        = number
}

variable "agent_token" {
  description = "Coder agent token"
  type        = string
  sensitive   = true
}

variable "agent_init_script" {
  description = "Coder agent initialization script"
  type        = string
}

variable "coder_access_url" {
  description = "URL for Coder instance (e.g., http://coder:7080)"
  type        = string
  default     = "http://coder:7080"
}

variable "workspace_dir" {
  description = "Host path for workspace projects (optional bind mount)"
  type        = string
  default     = ""
}

variable "ssh_key_dir" {
  description = "Host path for SSH keys (optional bind mount)"
  type        = string
  default     = ""
}

variable "traefik_auth_dir" {
  description = "Host path for Traefik auth files"
  type        = string
  default     = "/mnt/workspace/wcp-coder/config/traefik/auth"
}

variable "traefik_labels" {
  description = "Map of Traefik routing labels"
  type        = map(string)
  default     = {}
}

variable "ssh_enabled" {
  description = "Whether SSH is enabled"
  type        = bool
  default     = false
}

variable "ssh_port" {
  description = "SSH port to publish"
  type        = string
  default     = "2222"
}

variable "container_image" {
  description = "Docker image for workspace container"
  type        = string
  default     = "codercom/enterprise-base:ubuntu"
}

variable "docker_network" {
  description = "Docker network name"
  type        = string
  default     = "coder-network"
}

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

# =============================================================================
# Docker Resources
# =============================================================================

resource "docker_volume" "home_volume" {
  name = "coder-${var.workspace_id}-home"
  
  lifecycle {
    ignore_changes = all
  }
  
  labels {
    label = "coder.owner"
    value = var.workspace_owner_name
  }
  labels {
    label = "coder.owner_id"
    value = var.workspace_owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = var.workspace_id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = var.workspace_name
  }
}

resource "null_resource" "ensure_host_workspace_dir" {
  triggers = {
    workspace_name = var.workspace_name
    root_dir       = var.workspace_dir
  }

  provisioner "local-exec" {
    command = "sh -lc 'if [ -n \"${var.workspace_dir}\" ]; then mkdir -p /workspace/${var.workspace_name}; fi'"
  }
}

resource "docker_container" "workspace" {
  count      = var.workspace_start_count
  image      = var.container_image
  privileged = true  # Required for Docker-in-Docker
  
  depends_on = [
    null_resource.ensure_host_workspace_dir
  ]
  
  name     = "coder-${var.workspace_owner_name}-${lower(var.workspace_name)}"
  hostname = var.workspace_name
  
  entrypoint = [
    "sh",
    "-c",
    "echo \"[DEBUG] CODER_ACCESS_URL is: $1\"; cat > /tmp/init_script.sh <<'INIT_SCRIPT'\n${var.agent_init_script}\nINIT_SCRIPT\n# Replace any hardcoded localhost URL with the runtime CODER_ACCESS_URL (provided as $1)\nsed -i \"s|http://localhost:7080|$1|g\" /tmp/init_script.sh\n# Execute the fixed init script\nsh /tmp/init_script.sh",
    "unused",
    var.coder_access_url
  ]
  
  env = [
    "CODER_AGENT_TOKEN=${var.agent_token}",
    "CODER_ACCESS_URL=${var.coder_access_url}"
  ]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  networks_advanced {
    name = var.docker_network
  }
  
  # Persistent home directory
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Optional host bind mount for workspace files
  dynamic "mounts" {
    for_each = var.workspace_dir != "" ? [
      trimsuffix(var.workspace_dir, "/")
    ] : []
    content {
      target    = "/home/coder/workspace"
      source    = "${mounts.value}/${var.workspace_name}"
      type      = "bind"
      read_only = false
    }
  }
  
  # Traefik authentication files
  mounts {
    target = "/traefik-auth"
    source = var.traefik_auth_dir
    type   = "bind"
  }

  # Optional SSH keys directory
  dynamic "mounts" {
    for_each = var.ssh_key_dir != "" ? [
      trimsuffix(var.ssh_key_dir, "/")
    ] : []
    content {
      target = "/mnt/host-ssh"
      source = mounts.value
      type   = "bind"
    }
  }

  # Coder metadata labels
  labels {
    label = "coder.owner"
    value = var.workspace_owner_name
  }
  labels {
    label = "coder.owner_id"
    value = var.workspace_owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = var.workspace_id
  }
  labels {
    label = "coder.workspace_name"
    value = var.workspace_name
  }
  
  # Traefik routing labels
  dynamic "labels" {
    for_each = var.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Optionally publish SSH port
  dynamic "ports" {
    for_each = var.ssh_enabled ? [1] : []
    content {
      internal = 2222
      external = tonumber(var.ssh_port)
      protocol = "tcp"
    }
  }
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

output "home_volume_name" {
  description = "Name of the home volume"
  value       = docker_volume.home_volume.name
}

output "container_id" {
  description = "Container ID (if started)"
  value       = try(docker_container.workspace[0].id, "")
}
