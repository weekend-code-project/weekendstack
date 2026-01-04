# =============================================================================
# MODULE: VS Code Server
# =============================================================================
# DESCRIPTION:
#   Configures VS Code Server (code-server) as the web-based IDE for workspaces.
#   Uses the official Coder registry module for code-server.
#
# ARCHITECTURE:
#   - Provides "VS Code" button in Coder UI
#   - Opens to specified folder (default: /home/coder/workspace)
#   - Customizable settings and extensions
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

# =============================================================================
# Code Server App
# =============================================================================

resource "coder_app" "code_server" {
  agent_id     = var.agent_id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337?folder=${var.folder}"
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
# Outputs
# =============================================================================

output "code_server_id" {
  description = "Code server app ID"
  value       = coder_app.code_server.id
}
