# =============================================================================
# Coder Node.js Template - Modular Architecture
# =============================================================================
# A modular template for creating Node.js development workspaces.
#
# FEATURES:
# - Git integration with SSH keys and GitHub CLI
# - VS Code Server (browser-based IDE) with Node tooling
# - Optional Docker-in-Docker support
# - Node.js runtime (image includes latest LTS)
# - Traefik routing with optional authentication
# - SSH server access with dynamic port allocation
# - Static site server with auto-generated HTML
#
# FILE STRUCTURE:
# - main.tf: Core Terraform config and data sources (this file)
# - variables.tf: Environment variables (workspace_dir, ssh_key_dir, etc.)
# - resources.tf: Docker container, volumes, and core resources
# - module-*.tf: Self-contained feature modules with parameters
#
# MODULE PATTERN:
# Each module file contains:
# 1. Parameters (data.coder_parameter) - User-configurable options
# 2. Module declaration or local logic - Feature implementation
# 3. Integration points - Used by resources.tf or module-agent.tf
#
# VERSIONS:
# - v27: Initial modular refactor
# - v29: Docker-in-Docker working
# - v32: Traefik local implementation (current)
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
# Parameters
# =============================================================================

data "coder_parameter" "startup_command" {
  name        = "Startup Command"
  description = "Command to run at the end of startup."
  type        = "string"
  default     = "npm run dev -- --port $PORT --host 0.0.0.0"
  mutable     = true
}

data "coder_parameter" "auto_generate_html" {
  name        = "Auto-generate HTML"
  description = "Automatically generate index.html if it doesn't exist"
  type        = "bool"
  default     = true
  mutable     = false
}

# =============================================================================
# Locals
# =============================================================================

locals {
  username = data.coder_workspace_owner.me.name
  
  # Workspace home directory path
  workspace_home_dir = "${var.workspace_dir}/${data.coder_workspace.me.name}"
}
