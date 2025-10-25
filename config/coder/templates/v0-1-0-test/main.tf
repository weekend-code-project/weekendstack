terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username = data.coder_workspace_owner.me.name
}

# =============================================================================
# Parameters
# =============================================================================

# SSH Parameters - see ssh-params.tf

# =============================================================================
# Workspace Secret
# =============================================================================

resource "random_password" "workspace_secret" {
  length  = 16
  special = false
}

# =============================================================================
# Test: Using Git-Based Modules
# =============================================================================
# This template tests migrated git-based modules incrementally

# Module 1: Init Shell (simplest)
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/init-shell?ref=v0.1.0"
}

# Module 2: Git Identity
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-identity?ref=v0.1.0"
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

# Module 3: SSH Integration
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/ssh-integration?ref=v0.1.0"
  
  workspace_id          = data.coder_workspace.me.id
  workspace_password    = random_password.workspace_secret.result
  ssh_enable_default    = data.coder_parameter.ssh_enable.value
  ssh_port_mode_default = try(data.coder_parameter.ssh_port_mode[0].value, "auto")
  ssh_port_default      = try(data.coder_parameter.ssh_port[0].value, "")
}

# =============================================================================
# Coder Agent
# =============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # Compose startup script from module outputs
  startup_script = join("\n", [
    "#!/bin/bash",
    "set -e",
    "echo '[WORKSPACE] 🚀 Starting workspace ${data.coder_workspace.me.name}'",
    "",
    module.init_shell.setup_script,
    "",
    module.git_identity.setup_script,
    "",
    module.ssh.ssh_copy_script,
    "",
    "# TODO: Add more modules as we migrate them",
    "",
    module.ssh.ssh_setup_script,
    "",
    "echo '[WORKSPACE] ✅ Workspace ready!'",
  ])

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    SSH_PORT            = module.ssh.ssh_port
  }

  # Basic monitoring
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
    display_name = "Disk Usage"
    key          = "home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }
}

# =============================================================================
# VS Code App
# =============================================================================

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

# =============================================================================
# Docker Resources
# =============================================================================

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  privileged = true
  
  name     = "coder-${local.username}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  
  command = [
    "sh", "-c",
    <<-EOT
    coder agent --agent-url http://coder:7080 --agent-token ${coder_agent.main.token}
    EOT
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
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

  # SSH port (if enabled)
  dynamic "ports" {
    for_each = module.ssh.ssh_enabled ? [1] : []
    content {
      internal = 2222
      external = tonumber(module.ssh.ssh_port)
    }
  }

  labels {
    label = "coder.owner"
    value = local.username
  }
  
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
