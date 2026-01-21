terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# Workspace metadata
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# Docker provider configuration
provider "docker" {}

# Random provider configuration
provider "random" {}

# Workspace secret password (for SSH, etc.)
resource "random_password" "workspace_secret" {
  length  = 16
  special = false
  keepers = {
    workspace_id = data.coder_workspace.me.id
  }
}

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
  base_domain        = var.base_domain
  actual_base_domain = var.base_domain
}

# Collect custom metadata blocks from modules
locals {
  all_custom_metadata = concat(
    try(module.docker[0].metadata_blocks, []),
    try(module.ssh.metadata_blocks, [])
  )
}

# Metadata module
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata-module?ref=PLACEHOLDER"
  
  enabled_blocks = data.coder_parameter.metadata_blocks.value != "" ? jsondecode(data.coder_parameter.metadata_blocks.value) : []
  custom_blocks  = local.all_custom_metadata
}

# Core modules (always loaded, no conditional count)
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=PLACEHOLDER"
}

module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace"
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
  
  # Mount Traefik auth directory (conditionally when password is set)
  dynamic "volumes" {
    for_each = try(data.coder_parameter.workspace_secret.value, "") != "" ? [1] : []
    content {
      container_path = "/traefik-auth"
      host_path      = var.traefik_auth_dir
      read_only      = false
    }
  }
  
  # Dynamic port mappings (added by modules)
  # SSH port mapping (when SSH is enabled)
  dynamic "ports" {
    for_each = data.coder_parameter.ssh_enable.value ? [1] : []
    content {
      internal = 2222
      external = tonumber(module.ssh[0].ssh_port)
      protocol = "tcp"
    }
  }
  
  # Server port mappings (when server is configured)
  # Note: Using hardcoded port 8080 for now (inline setup-server script)
  dynamic "ports" {
    for_each = local.auto_generate_html ? [1] : []
    content {
      internal = 8080
      external = 8080
      protocol = "tcp"
    }
  }
  
  # Traefik labels (static for testing)
  labels {
    label = "traefik.enable"
    value = "true"
  }
  
  labels {
    label = "traefik.docker.network"
    value = "coder-network"
  }
  
  labels {
    label = "traefik.http.routers.${lower(data.coder_workspace.me.name)}.rule"
    value = "Host(`${lower(data.coder_workspace.me.name)}.${var.base_domain}`)"
  }
  
  labels {
    label = "traefik.http.routers.${lower(data.coder_workspace.me.name)}.entrypoints"
    value = "websecure"
  }
  
  labels {
    label = "traefik.http.routers.${lower(data.coder_workspace.me.name)}.tls"
    value = "true"
  }
  
  labels {
    label = "traefik.http.services.${lower(data.coder_workspace.me.name)}.loadbalancer.server.port"
    value = "8080"
  }
  
  labels {
    label = "traefik.http.routers.${lower(data.coder_workspace.me.name)}.middlewares"
    value = "${lower(data.coder_workspace.me.name)}-auth"
  }
  
  labels {
    label = "traefik.http.middlewares.${lower(data.coder_workspace.me.name)}-auth.basicauth.usersfile"
    value = "/traefik-auth/hashed_password-${data.coder_workspace.me.name}"
  }
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
