# =============================================================================
# Coder Docker Template
# =============================================================================
# A modular template for creating Docker-based development workspaces with:
# - Git integration and SSH support
# - Code Server (VS Code in browser)
# - Configurable static site server
# - Optional GitHub CLI installation
# - SSH access
#
# Structure:
# - main.tf: Core Terraform configuration and data sources
# - variables.tf: Environment variables
# - modules.tf: Module declarations
# - resources.tf: Docker resources
# - *-params.tf: Parameter definitions (git, ssh, metadata, etc.)
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

# =============================================================================
# Locals
# =============================================================================

locals {
  username = data.coder_workspace_owner.me.name
  
  # Workspace home directory path
  workspace_home_dir = "${var.workspace_dir}/${data.coder_workspace.me.name}"
}
