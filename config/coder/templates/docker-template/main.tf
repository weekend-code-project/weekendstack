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
# Variables (from environment)
# =============================================================================

variable "workspace_dir" {
  description = "Host directory for workspace files"
  type        = string
  default     = ""
  sensitive   = false
}

variable "ssh_key_dir" {
  description = "Host directory for SSH keys"
  type        = string
  default     = ""
  sensitive   = false
}

variable "traefik_auth_dir" {
  description = "Host directory for Traefik auth files"
  type        = string
  default     = "/mnt/workspace/wcp-coder/config/traefik/auth"
  sensitive   = false
}

# =============================================================================
# Parameters
# =============================================================================

# SSH Parameters - see ssh-params.tf
# Metadata Parameters - see metadata-params.tf

# =============================================================================
# Workspace Secret
# =============================================================================

resource "random_password" "workspace_secret" {
  length  = 16
  special = false
}

# =============================================================================
# Modules
# =============================================================================

# Metadata configuration
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/metadata?ref=v0.1.0"
  
  # Multi-select with form_type="multi-select" returns JSON array of selected values
  # Parse the JSON to get the list: ["cpu", "ram", "disk"]
  enabled_blocks = data.coder_parameter.metadata_blocks.value != "" ? jsondecode(data.coder_parameter.metadata_blocks.value) : []
}

# Init Shell
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/init-shell?ref=v0.1.0"
}

# Git Identity (automatic Git configuration)
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-identity?ref=v0.1.0"
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

# Git Integration (repository cloning)
module "git_integration" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-integration?ref=v0.1.0"
  
  github_repo_url = data.coder_parameter.clone_repo.value ? data.coder_parameter.github_repo[0].value : ""
}

# GitHub CLI Installation
module "github_cli" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/github-cli?ref=v0.1.0"
}

# SSH Integration
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/ssh-integration?ref=v0.1.0"
  
  workspace_id          = data.coder_workspace.me.id
  workspace_password    = try(data.coder_parameter.ssh_password[0].value, "") != "" ? try(data.coder_parameter.ssh_password[0].value, "") : random_password.workspace_secret.result
  ssh_enable_default    = data.coder_parameter.ssh_enable.value
  ssh_port_mode_default = try(data.coder_parameter.ssh_port_mode[0].value, "auto")
  ssh_port_default      = try(data.coder_parameter.ssh_port[0].value, "")
}

# Docker Scripts (install + config only) - COMMENTED OUT FOR TESTING
# module "docker" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/docker-integration?ref=v0.1.0"
# }

# Routing Labels Test - Testing if module name matters
module "routing_labels_test" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/routing-labels-test?ref=v0.1.0"
  
  workspace_name     = data.coder_workspace.me.name
  workspace_owner    = data.coder_workspace_owner.me.name
  workspace_id       = data.coder_workspace.me.id
  workspace_owner_id = data.coder_workspace_owner.me.id
  make_public        = data.coder_parameter.make_public.value
  exposed_ports_list = local.exposed_ports_list
}

# Traefik Routing Test - Minimal module to debug validation issue
# module "traefik_routing_test" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/traefik-routing-test?ref=v0.1.0"
#   
#   workspace_name = data.coder_workspace.me.name
# }

# Traefik Routing - COMMENTED OUT FOR TESTING
# module "traefik_routing" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/traefik-routing?ref=v0.1.0"
#   
#   workspace_name     = data.coder_workspace.me.name
#   workspace_owner    = data.coder_workspace_owner.me.name
#   workspace_id       = data.coder_workspace.me.id
#   workspace_owner_id = data.coder_workspace_owner.me.id
#   make_public        = data.coder_parameter.make_public.value
#   exposed_ports_list = local.exposed_ports_list
# }

# Traefik Authentication - COMMENTED OUT FOR TESTING
# module "traefik_auth" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/traefik-auth?ref=v0.1.0"
#   
#   workspace_name   = data.coder_workspace.me.name
#   workspace_owner  = data.coder_workspace_owner.me.name
#   make_public      = data.coder_parameter.make_public.value
#   workspace_secret = try(data.coder_parameter.workspace_secret[0].value, "") != "" ? try(data.coder_parameter.workspace_secret[0].value, "") : random_password.workspace_secret.result
# }

# Coder Agent
module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.0"
  
  arch       = data.coder_provisioner.me.arch
  os         = "linux"
  
  depends_on = [
    null_resource.ensure_workspace_folder
  ]
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "set -e",
    "echo '[WORKSPACE] 🚀 Starting workspace ${data.coder_workspace.me.name}'",
    "",
    module.init_shell.setup_script,
    module.git_identity.setup_script,
    module.ssh.ssh_copy_script,
    module.git_integration.clone_script,
    (data.coder_parameter.clone_repo.value && try(data.coder_parameter.install_github_cli[0].value, false)) ? module.github_cli.install_script : "",
    # module.docker.docker_install_script,
    # module.docker.docker_config_script,
    module.ssh.ssh_setup_script,
    # module.traefik_auth.traefik_auth_setup_script,
    module.setup_server.setup_server_script,
    "",
    "echo '[WORKSPACE] ✅ Workspace ready!'",
    "echo '[WORKSPACE] 🌐 Server URL: http://localhost:8080'",
  ])
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = "http://coder:7080"
  
  env_vars = {
    SSH_PORT = module.ssh.ssh_port
  }
  
  metadata_blocks = module.metadata.metadata_blocks
}

# Setup Server (starts the static site server and runs startup command)
module "setup_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.0"
  
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  auto_generate_html    = data.coder_parameter.auto_generate_html.value
  exposed_ports_list    = local.exposed_ports_list
  startup_command       = try(data.coder_parameter.startup_command[0].value, "")
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  workspace_url         = "http://localhost:8080"
}

# Code Server (VS Code in browser)
module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/code-server?ref=v0.1.0"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace"
}

# Preview Link (external Traefik URL) - COMMENTED OUT FOR TESTING
# module "preview_link" {
#   source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/preview-link?ref=v0.1.0"
#   
#   agent_id              = module.agent.agent_id
#   workspace_url         = "http://placeholder.url"
#   workspace_start_count = data.coder_workspace.me.start_count
#   use_custom_url        = data.coder_parameter.use_custom_preview_url.value
#   custom_url            = try(data.coder_parameter.custom_preview_url[0].value, "")
# }

# =============================================================================
# Docker Resources
# =============================================================================

# Create workspace directory inside Coder's /workspace mount
resource "null_resource" "ensure_workspace_folder" {
  provisioner "local-exec" {
    command = "mkdir -p /workspace/${data.coder_workspace.me.name}"
  }
  
  triggers = {
    workspace_id = data.coder_workspace.me.id
  }
}

# Local variable for workspace home directory path
locals {
  workspace_home_dir = "${var.workspace_dir}/${data.coder_workspace.me.name}"
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  privileged = true
  
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  
  # Ensure container is removed when workspace stops
  must_run              = true
  destroy_grace_seconds = 10
  
  entrypoint = [
    "sh",
    "-c",
    replace(module.agent.agent_init_script, "http://localhost:7080", "http://coder:7080"),
  ]
  
  env = [
    "CODER_AGENT_TOKEN=${module.agent.agent_token}",
    "CODER_ACCESS_URL=http://coder:7080"
  ]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  networks_advanced {
    name = "coder-network"
  }
  
  # Bind mount workspace directory from host
  # Each workspace gets its own folder: /workspace/${workspace_name} (inside Coder container)
  # which maps to files/coder/workspace/${workspace_name} on the host
  mounts {
    target = "/home/coder/workspace"
    source = local.workspace_home_dir
    type   = "bind"
  }

  # Mount SSH keys from host (read-only)
  mounts {
    target    = "/mnt/host-ssh"
    source    = var.ssh_key_dir
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/traefik-auth"
    source = var.traefik_auth_dir
    type   = "bind"
  }

  # Traefik labels for routing - COMMENTED OUT FOR TESTING
  # dynamic "labels" {
  #   for_each = module.traefik_routing.traefik_labels
  #   content {
  #     label = labels.key
  #     value = labels.value
  #   }
  # }

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
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }

  dynamic "ports" {
    for_each = module.ssh.ssh_enabled ? [1] : []
    content {
      internal = 2222
      external = tonumber(module.ssh.ssh_port)
      protocol = "tcp"
    }
  }
}
