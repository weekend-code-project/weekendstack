# =============================================================================
# TEMPLATE: Test Module Template (POC)
# =============================================================================
# PURPOSE:
#   Test whether Coder templates can reference external Terraform modules
#   using the standard module source syntax.
#
# STRUCTURE:
#   This template uses a proper Terraform module located at:
#   ../test-modules/docker-workspace/
#
# HYPOTHESIS:
#   When we run `coder templates push`, Terraform should:
#   1. Run `terraform init` to resolve module sources
#   2. Follow the relative path to find the module
#   3. Bundle everything and upload to Coder
#
# SUCCESS CRITERIA:
#   ✅ terraform init succeeds (finds module)
#   ✅ coder templates push succeeds
#   ✅ Can create a workspace from this template
#   ✅ Workspace provisions correctly
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

# =============================================================================
# Module Reference (THE KEY PART OF THIS POC)
# =============================================================================

module "workspace" {
  source = "../test-modules/docker-workspace"
  
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
    name           = data.coder_workspace.me.name
    owner          = data.coder_workspace_owner.me.name
    container_id   = module.workspace.container_id
    volume_name    = module.workspace.home_volume_name
  }
  description = "Workspace information from the module"
}
