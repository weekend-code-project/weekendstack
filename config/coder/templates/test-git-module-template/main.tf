# =============================================================================
# TEMPLATE: Test Git Module Template (POC)
# =============================================================================
# PURPOSE:
#   Test whether Coder templates can reference Terraform modules from Git
#   sources (including the same repository).
#
# MODULE SOURCE:
#   References the docker-workspace-git module from this same repository
#   using Git URL syntax.
#
# HYPOTHESIS:
#   When we run `coder templates push`, Terraform should:
#   1. Run `terraform init` which fetches the module from Git
#   2. Clone the repo and extract the module subdirectory
#   3. Bundle everything and upload to Coder
#
# =============================================================================

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
# Data Sources
# =============================================================================

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "docker_image" {
  name         = "docker_image"
  display_name = "Docker Image"
  description  = "Which Docker image would you like to use?"
  default      = "codercom/enterprise-base:ubuntu"
  type         = "string"
  mutable      = true
  icon         = "/icon/docker.svg"
  
  option {
    name  = "Ubuntu (Base)"
    value = "codercom/enterprise-base:ubuntu"
    icon  = "/icon/ubuntu.svg"
  }
  
  option {
    name  = "Node.js"
    value = "codercom/enterprise-node:ubuntu"
    icon  = "/icon/nodejs.svg"
  }
}

data "coder_parameter" "container_cpu" {
  name         = "container_cpu"
  display_name = "Container CPU"
  description  = "CPU shares (1024 = 1 CPU)"
  default      = "2048"
  type         = "number"
  mutable      = true
  icon         = "/icon/memory.svg"
  
  option {
    name  = "1 CPU"
    value = "1024"
  }
  
  option {
    name  = "2 CPUs"
    value = "2048"
  }
  
  option {
    name  = "4 CPUs"
    value = "4096"
  }
}

data "coder_parameter" "container_memory" {
  name         = "container_memory"
  display_name = "Container Memory"
  description  = "Memory limit in MB"
  default      = "4096"
  type         = "number"
  mutable      = true
  icon         = "/icon/memory.svg"
  
  option {
    name  = "2 GB"
    value = "2048"
  }
  
  option {
    name  = "4 GB"
    value = "4096"
  }
  
  option {
    name  = "8 GB"
    value = "8192"
  }
}

# -----------------------------------------------------------------------------
# SSH Parameters (show when SSH enabled; port shown only for manual mode)
# -----------------------------------------------------------------------------
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for direct SSH access."
  type         = "bool"
  default      = false
  mutable      = true
  order        = 50
}

data "coder_parameter" "ssh_port_mode" {
  name         = "ssh_port_mode"
  display_name = "SSH Port Mode"
  description  = "Choose 'manual' to specify a port, or 'auto' to pick a stable open port automatically."
  type         = "string"
  default      = "auto"
  mutable      = true
  option {
    name  = "auto"
    value = "auto"
  }
  option {
    name  = "manual"
    value = "manual"
  }
  order = 51
}

# Only show the SSH port field when SSH is enabled AND the port mode is set to manual
data "coder_parameter" "ssh_port" {
  name         = "ssh_port"
  display_name = "SSH Port"
  description  = "Container port to run sshd on (also published on the router as needed)."
  type         = "string"
  default      = ""
  mutable      = true
  count        = data.coder_parameter.ssh_enable.value ? (data.coder_parameter.ssh_port_mode.value == "manual" ? 1 : 0) : 0
  order        = 52
}

# =============================================================================
# Module Reference via Git (THE KEY PART OF THIS POC)
# =============================================================================

module "workspace" {
  # Git source format: git::<repo_url>//<path_to_module>?ref=<branch>
  # NOTE: Update the branch name to match your current branch
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/test-modules/docker-workspace?ref=v0.1.0"
  
  # Workspace identification (from Coder data sources)
  workspace_name     = data.coder_workspace.me.name
  workspace_owner    = data.coder_workspace_owner.me.name
  workspace_owner_id = data.coder_workspace_owner.me.id
  workspace_id       = data.coder_workspace.me.id
  workspace_state    = data.coder_workspace.me.transition
  
  # Docker configuration (from parameters)
  docker_image     = data.coder_parameter.docker_image.value
  container_cpu    = data.coder_parameter.container_cpu.value
  container_memory = data.coder_parameter.container_memory.value
  
  # Agent configuration
  agent_arch = data.coder_provisioner.me.arch
  
  # Git configuration
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

# =============================================================================
# Code Server (VS Code in browser)
# =============================================================================

resource "coder_app" "code-server" {
  agent_id     = module.workspace.agent_id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

# =============================================================================
# Outputs (for debugging)
# =============================================================================

output "workspace_info" {
  value = {
    name         = data.coder_workspace.me.name
    owner        = data.coder_workspace_owner.me.name
    container_id = module.workspace.container_id
    volume_name  = module.workspace.home_volume_name
  }
  description = "Workspace information from the Git module"
}
