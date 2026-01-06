# =============================================================================
# MODULE: VS Code Server
# =============================================================================
# DESCRIPTION:
#   Configures VS Code Server (code-server) as the web-based IDE for workspaces.
#   Uses the official Coder registry module for code-server.
#
# ARCHITECTURE:
#   - Provides "VS Code" button in Coder UI (opens to workspace folder)
#   - Terminal always starts in workspace folder (not home directory)
#   - Customizable settings and extensions
#   - Does NOT include VS Code Desktop button (web-based only)
#
# DEPENDENCIES:
#   - coder_agent (agent must be created first)
#   - data.coder_workspace (for start_count)
#
# OUTPUTS:
#   - code_server_id: Code server app ID
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

variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "workspace_start_count" {
  description = "Number of times workspace has started"
  type        = number
}

variable "folder" {
  description = "Folder to open in VS Code"
  type        = string
  default     = "/home/coder/workspace"
}

variable "order" {
  description = "Display order in UI"
  type        = number
  default     = 1
}

variable "settings" {
  description = "VS Code settings"
  type        = map(any)
  default = {
    "editor.tabSize"               = 2
    "workbench.colorTheme"         = "Default Dark+"
    "editor.fontSize"              = 18
    "terminal.integrated.fontSize" = 18
    "workbench.startupEditor"      = "none"
    "workbench.iconTheme"          = "let-icons"
  }
}

variable "extensions" {
  description = "VS Code extensions to install"
  type        = list(string)
  default     = []
}

# =============================================================================
# Code Server Module
# =============================================================================

module "code_server" {
  count   = var.workspace_start_count
  source  = "registry.coder.com/modules/code-server/coder"
  version = ">= 1.0.0"
  
  folder     = var.folder
  agent_id   = var.agent_id
  order      = var.order
  settings   = var.settings
  extensions = var.extensions
}

# =============================================================================
# Outputs
# =============================================================================

output "code_server_id" {
  description = "Code server app ID"
  value       = try(module.code_server[0].id, "")
}
