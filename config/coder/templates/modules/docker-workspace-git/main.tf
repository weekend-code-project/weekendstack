# =============================================================================
# MODULE: Docker Workspace (POC)
# =============================================================================
# DESCRIPTION:
#   A proper Terraform module that encapsulates basic Docker workspace setup.
#   This is a POC to test if Coder templates can reference external modules.
#
# INPUTS:
#   - workspace_name: Name of the workspace
#   - workspace_owner: Owner's username
#   - docker_image: Docker image to use
#   - container_cpu: CPU limit
#   - container_memory: Memory limit
#
# OUTPUTS:
#   - agent_token: The Coder agent token
#   - container_id: Docker container ID
#
# =============================================================================

# Required providers (inherited from root module, but declared for clarity)
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

# =============================================================================
# Coder Agent
# =============================================================================

resource "coder_agent" "main" {
  arch = var.agent_arch
  os   = "linux"

  startup_script = <<-EOT
    #!/bin/bash
    set -e
    
    echo "[WORKSPACE] 🚀 Initializing workspace: ${var.workspace_name}"
    echo "[WORKSPACE] 👤 Owner: ${var.workspace_owner}"
    echo "[WORKSPACE] 🐳 Image: ${var.docker_image}"
    
    # Create home directory structure
    mkdir -p ~/workspace
    
    # Set Git identity
    git config --global user.name "${var.git_author_name}"
    git config --global user.email "${var.git_author_email}"
    
    echo "[WORKSPACE] ✅ Workspace ready!"
  EOT

  env = {
    GIT_AUTHOR_NAME     = var.git_author_name
    GIT_AUTHOR_EMAIL    = var.git_author_email
    GIT_COMMITTER_NAME  = var.git_author_name
    GIT_COMMITTER_EMAIL = var.git_author_email
  }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }
}

# =============================================================================
# Docker Resources
# =============================================================================

resource "docker_volume" "home_volume" {
  name = "coder-${var.workspace_owner}-${var.workspace_name}-home"
}

resource "docker_image" "workspace" {
  name = var.docker_image
}

resource "docker_container" "workspace" {
  count = var.workspace_state == "start" ? 1 : 0
  
  image    = docker_image.workspace.name
  name     = "coder-${var.workspace_owner}-${var.workspace_name}"
  hostname = var.workspace_name
  
  # DNS
  dns = ["1.1.1.1"]
  
  # Add labels in Docker to keep track of orphan resources
  labels {
    label = "coder.owner"
    value = var.workspace_owner
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
  
  # Resource limits
  cpu_shares = var.container_cpu
  memory     = var.container_memory
  
  # Home volume
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  
  # Coder agent token
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}
