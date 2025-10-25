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
}

# =============================================================================
# Dynamic Parameters
# =============================================================================
# Dynamic parameters will be added here as modules are refactored.
# Each module may expose its own parameters for workspace customization.

# =============================================================================
# Module Resources
# =============================================================================
# All resources are now defined in their respective module files:
#
# - workspace-secret.tf  : Random password and metadata
# - coder-agent.tf       : Agent configuration and startup script
# - code-server.tf       : VS Code Server IDE
# - docker-resources.tf  : Docker volume and container
# - init-shell.tf        : Home directory initialization
# - install-docker.tf    : Docker Engine installation
# - docker-config.tf     : Docker-in-Docker daemon setup
#
# The modules are bundled into the template root during push via:
# config/coder/scripts/push-templates.sh
# =============================================================================

// metadata blocks are provided by the bundled file `metadata-blocks.tf`
// which will be copied to the template root during push. That file
// defines `local.metadata_blocks` directly so we don't duplicate it here.
