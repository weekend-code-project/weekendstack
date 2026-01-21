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

# Workspace container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  
  hostname = data.coder_workspace.me.name
  
  # Required for Docker-in-Docker
  privileged = true
  
  # Connect to coder-network for Traefik routing
  networks_advanced {
    name = "coder-network"
  }
  
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(module.agent.agent_init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  env = ["CODER_AGENT_TOKEN=${module.agent.agent_token}"]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  
  # Mount SSH keys from host VM to workspace
  # This mounts the actual SSH directory from the Docker host (e.g., /home/docker/.ssh)
  volumes {
    container_path = "/mnt/host-ssh"
    host_path      = local.resolved_ssh_key_dir
    read_only      = true
  }
  
  # Mount Traefik auth directory (for password-protected workspaces)
  volumes {
    container_path = "/traefik-auth"
    host_path      = local.resolved_traefik_auth_dir
    read_only      = false
  }
  
  # SSH port mapping (conditional - only when SSH is enabled)
  dynamic "ports" {
    for_each = try(module.ssh[0].docker_ports, null) != null ? [module.ssh[0].docker_ports] : []
    content {
      internal = ports.value.internal
      external = ports.value.external
      protocol = "tcp"
    }
  }
  
  # Server port mappings (conditional - only when server is configured)
  dynamic "ports" {
    for_each = try(module.setup_server[0].docker_ports, [])
    content {
      internal = ports.value.internal
      external = ports.value.external
      protocol = "tcp"
    }
  }
  
  # Traefik routing labels (conditional - only when Traefik module is enabled)
  dynamic "labels" {
    for_each = try(module.traefik[0].traefik_labels, {})
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# Home volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-home"
  
  lifecycle {
    ignore_changes = all
  }
  
  # Hide from Glance dashboard
  labels {
    label = "glance.hide"
    value = "true"
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
# Phase 1 Modules: Zero Coder Dependencies (No UI Parameters)
# =============================================================================

# Module: init-shell
# Issue #23 - Simplest baseline module (0 params, no deps)
# Pure git module call with zero parameters and no Coder dependencies
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=v0.1.0"
}

# Module: debug-domain (base domain local)
# Issue #25 - Base domain config (0 params, uses var.base_domain)
# Pure local variable definition with zero Coder dependencies
locals {
  actual_base_domain       = var.base_domain
  resolved_ssh_key_dir     = trimspace(var.ssh_key_dir) != "" ? var.ssh_key_dir : "/home/docker/.ssh"
  resolved_traefik_auth_dir = trimspace(var.traefik_auth_dir) != "" ? var.traefik_auth_dir : "/opt/stacks/weekendstack/config/traefik/auth"
}

# =============================================================================
# Phase 2 Modules: Coder Data Sources Only (No UI Parameters)
# =============================================================================

# Module: code-server
# Issue #24 - VS Code web IDE (0 params, depends on agent)
# Uses Coder data sources but no UI parameters - tests data source integration
module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=v0.1.0"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace"
}

# =============================================================================
# Phase 3 Modules: Simple UI Parameters (Boolean Toggles)
# =============================================================================

# Module: docker (Issue #26)
# Overlaid from docker-params.tf
# Provides Docker-in-Docker with enable_docker boolean parameter

# =============================================================================
# Phase 4 Modules: Multi-Select Parameters
# =============================================================================

# Module: metadata (Issue #27)
# Overlaid from metadata-params.tf
# Provides resource monitoring metadata blocks (CPU, RAM, disk, etc.)

# =============================================================================
# Phase 5 Modules: Complex Conditional Parameters
# =============================================================================

# Module: ssh (Issue #33)
# Overlaid from ssh-params.tf
# Provides SSH server with enable toggle, port mode, and password configuration
# VERY HIGH flickering risk: conditional parameters with disabled styling

# Workspace secret for SSH password (if not manually set)
resource "random_password" "workspace_secret" {
  length  = 16
  special = true
}

# =============================================================================
# Preview Links
# =============================================================================

# Traefik preview link for workspace
resource "coder_app" "traefik_preview" {
  agent_id     = module.agent.agent_id
  slug         = "workspace"
  display_name = "Workspace Preview"
  icon         = "/icon/code.svg"
  url          = "https://${lower(data.coder_workspace.me.name)}.${var.base_domain}"
  external     = true
}
