# =============================================================================
# BASE TEMPLATE v2
# =============================================================================
# A minimal Coder workspace template for validation.
# This is the foundation that all other templates build upon.
#
# Features:
#   - Ubuntu container with Coder agent
#   - Home directory persistence via Docker volume
#   - Basic shell environment
#
# This template does NOT include:
#   - SSH access (add ssh module)
#   - Git integration (add git module)  
#   - Traefik routing (add traefik module)
#   - Code-server IDE (add code-server module)
#
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.0"
    }
  }
}

# =============================================================================
# PROVIDERS
# =============================================================================

provider "docker" {}

# =============================================================================
# CODER DATA SOURCES
# =============================================================================

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  # Workspace naming
  workspace_name = lower(data.coder_workspace.me.name)
  owner_name     = data.coder_workspace_owner.me.name
  container_name = "coder-${local.owner_name}-${local.workspace_name}"
  
  # Base image
  docker_image = "codercom/enterprise-base:ubuntu"
}

# =============================================================================
# DOCKER IMAGE
# =============================================================================

data "docker_registry_image" "workspace" {
  name = local.docker_image
}

resource "docker_image" "workspace" {
  name          = data.docker_registry_image.workspace.name
  pull_triggers = [data.docker_registry_image.workspace.sha256_digest]
  keep_locally  = true
}

# =============================================================================
# PERSISTENT STORAGE
# =============================================================================

resource "docker_volume" "home" {
  name = "coder-${local.owner_name}-${local.workspace_name}-home"
  
  lifecycle {
    # Keep volume when workspace is destroyed (data persistence)
    prevent_destroy = false
  }
}

# =============================================================================
# CODER AGENT
# =============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = "/home/coder"
  
  # Simple startup script - just log that we're ready
  startup_script = <<-SCRIPT
    #!/bin/bash
    echo "[STARTUP] 🚀 Workspace starting..."
    echo "[STARTUP] User: $(whoami)"
    echo "[STARTUP] Home: $HOME"
    echo "[STARTUP] ✅ Workspace ready!"
  SCRIPT
  
  # Git identity from Coder workspace owner
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }
  
  # Basic resource monitoring
  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
    interval     = 5
    timeout      = 1
  }
  
  metadata {
    display_name = "Memory Usage"
    key          = "memory"
    script       = "free -m | awk 'NR==2{printf \"%.1f%%\", $3*100/$2}'"
    interval     = 5
    timeout      = 1
  }
  
  metadata {
    display_name = "Disk Usage"
    key          = "disk"
    script       = "df -h /home/coder | awk 'NR==2{print $5}'"
    interval     = 60
    timeout      = 1
  }
}

# =============================================================================
# WORKSPACE CONTAINER
# =============================================================================

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  
  name     = local.container_name
  image    = docker_image.workspace.image_id
  hostname = local.workspace_name
  
  # Run the Coder agent init script
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  # Connect to coder network for internal communication
  networks_advanced {
    name = "coder-network"
  }
  
  # Home directory persistence
  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
  }
  
  # Basic environment
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]
  
  # Keep container running
  stdin_open = true
  tty        = true
  
  # Resource limits (reasonable defaults)
  memory = 2048  # 2GB
  
  # Lifecycle
  lifecycle {
    ignore_changes = [
      # Ignore changes to image to prevent recreation on pull
      image,
    ]
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "workspace_name" {
  value = local.workspace_name
}

output "container_name" {
  value = local.container_name
}
