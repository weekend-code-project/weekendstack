terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

# =============================================================================
# PHASE 0: BASELINE - ZERO PARAMETERS
# =============================================================================
# This is the absolute minimal template to establish a clean baseline.
# NO user parameters, NO conditional modules, NO complexity.
# Expected result: NO FLICKERING in Coder UI settings.
#
# If flickering occurs in Phase 0, the issue is in Coder itself or the
# base workspace configuration, not in our modular patterns.
# =============================================================================

# Workspace metadata (data sources only)
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# Docker provider configuration
provider "docker" {}

# Container image
data "docker_registry_image" "main" {
  name = "codercom/enterprise-base:ubuntu"
}

resource "docker_image" "main" {
  name          = data.docker_registry_image.main.name
  pull_triggers = [data.docker_registry_image.main.sha256_digest]
  keep_locally  = true
}

# Workspace container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  
  hostname = data.coder_workspace.me.name
  
  # Required for Docker-in-Docker (if we add it later)
  privileged = true
  
  # Connect to coder-network for Traefik routing
  networks_advanced {
    name = "coder-network"
  }
  
  # Minimal agent init (no modules, just basic agent token)
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  
  # Labels for identification
  labels {
    label = "coder.workspace"
    value = "true"
  }
}

# Home volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-home"
  
  lifecycle {
    ignore_changes = all
  }
  
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# =============================================================================
# Coder Agent - Minimal (No modules)
# =============================================================================
resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    set -e
    
    echo "🔧 [AGENT] Starting Coder agent..."
    
    # Basic workspace setup
    mkdir -p /home/coder/workspace
    cd /home/coder/workspace
    
    echo "✅ [AGENT] Workspace ready!"
  EOT
  
  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  
  metadata {
    display_name = "RAM Usage"
    key          = "ram"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  
  metadata {
    display_name = "Disk Usage"
    key          = "disk"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }
}

# =============================================================================
# Code Server (VS Code in browser) - Using module (zero parameters)
# =============================================================================
module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=PLACEHOLDER"
  
  agent_id              = coder_agent.main.id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace"
}
