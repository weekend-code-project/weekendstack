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

# Workspace metadata
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

# Base domain configuration
locals {
  base_domain = var.base_domain
}

# Core modules (always loaded, no conditional count)
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=PLACEHOLDER"
}

module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder"
}

# Workspace container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  
  hostname = data.coder_workspace.me.name
  
  # Connect to coder-network for Traefik routing
  networks_advanced {
    name = "coder-network"
  }
  
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(module.agent.agent_init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  # Enable privileged mode for Docker-in-Docker
  privileged = true
  
  env = [
    "CODER_AGENT_TOKEN=${module.agent.agent_token}",
  ]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  
  # Mount SSH keys from host
  volumes {
    container_path = "/home/coder/.ssh"
    host_path      = "/home/docker/.ssh"
    read_only      = true
  }
  
  # Mount Traefik auth directory
  volumes {
    container_path = "/traefik-auth"
    host_path      = "/opt/stacks/weekendstack/config/traefik/auth"
    read_only      = false
  }
  
  # Dynamic port mappings (added by modules)
  # dynamic "ports" {
  #   for_each = []
  #   content {
  #     internal = ports.value.internal
  #     external = ports.value.external
  #     protocol = "tcp"
  #   }
  # }
  
  # Dynamic Traefik labels (added by modules)
  # dynamic "labels" {
  #   for_each = {}
  #   content {
  #     label = labels.key
  #     value = labels.value
  #   }
  # }
}

# Home volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  
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
