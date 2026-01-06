# =============================================================================
# MODULE: Coder Agent
# =============================================================================
# DESCRIPTION:
#   Configures the Coder agent that runs inside the workspace container.
#   The agent connects to the Coder control plane and executes startup scripts.
#
# ARCHITECTURE:
#   - Agent runs inside workspace container
#   - Composes startup scripts from various modules
#   - Includes resource monitoring metadata
#   - Sets environment variables for Git identity
#
# DEPENDENCIES:
#   - data.coder_provisioner (architecture detection)
#   - Startup scripts from various modules (passed as variables)
#
# OUTPUTS:
#   - agent_id: Agent resource ID
#   - agent_token: Agent authentication token
#   - agent_init_script: Agent initialization script
#
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "arch" {
  description = "Architecture (amd64, arm64, etc.)"
  type        = string
}

variable "os" {
  description = "Operating system"
  type        = string
  default     = "linux"
}

variable "startup_script" {
  description = "Complete startup script (composed from modules)"
  type        = string
}

variable "git_author_name" {
  description = "Git author name"
  type        = string
}

variable "git_author_email" {
  description = "Git author email"
  type        = string
}

variable "coder_access_url" {
  description = "Coder instance URL"
  type        = string
  default     = "http://coder:7080"
}

variable "env_vars" {
  description = "Additional environment variables"
  type        = map(string)
  default     = {}
}

variable "metadata_blocks" {
  description = "List of metadata blocks for resource monitoring"
  type = list(object({
    display_name = string
    script       = string
    interval     = number
    timeout      = number
  }))
  default = []
}

# =============================================================================
# Agent Resource
# =============================================================================

resource "coder_agent" "main" {
  arch = var.arch
  os   = var.os
  dir  = "/home/coder/workspace"

  startup_script = var.startup_script

  # Disable VS Code Desktop button (web-based code-server only)
  display_apps {
    vscode = false
  }

  # Git identity configuration
  env = merge(
    {
      GIT_AUTHOR_NAME     = var.git_author_name
      GIT_AUTHOR_EMAIL    = var.git_author_email
      GIT_COMMITTER_NAME  = var.git_author_name
      GIT_COMMITTER_EMAIL = var.git_author_email
      CODER_ACCESS_URL    = var.coder_access_url
      CODER_WORKSPACE_DIR = "/home/coder/workspace"
    },
    var.env_vars
  )

  # Resource monitoring metadata
  dynamic "metadata" {
    for_each = toset(range(length(var.metadata_blocks)))
    content {
      display_name = var.metadata_blocks[metadata.key].display_name
      key          = format("%02d_%s", metadata.key + 1, replace(var.metadata_blocks[metadata.key].display_name, " ", "_"))
      script       = var.metadata_blocks[metadata.key].script
      interval     = var.metadata_blocks[metadata.key].interval
      timeout      = var.metadata_blocks[metadata.key].timeout
    }
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "agent_id" {
  description = "Agent resource ID"
  value       = coder_agent.main.id
}

output "agent_token" {
  description = "Agent authentication token"
  value       = coder_agent.main.token
  sensitive   = true
}

output "agent_init_script" {
  description = "Agent initialization script"
  value       = coder_agent.main.init_script
}
