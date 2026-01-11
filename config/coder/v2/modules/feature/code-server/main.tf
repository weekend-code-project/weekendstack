# =============================================================================
# MODULE: Code Server (VS Code Web IDE)
# =============================================================================
# Provides web-based VS Code IDE via code-server.
#
# Features:
#   - VS Code button in Coder UI
#   - Opens to /home/coder/workspace by default
#   - Customizable settings and extensions
#   - No VS Code Desktop button (web-only)
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
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
  description = "VS Code settings (JSON object)"
  type        = map(any)
  default = {
    "workbench.colorTheme"         = "Default Dark+"
    "workbench.startupEditor"      = "none"
    "editor.fontSize"              = 16
    "editor.tabSize"               = 2
    "terminal.integrated.fontSize" = 14
  }
}

variable "extensions" {
  description = "VS Code extensions to install"
  type        = list(string)
  default     = []
}

# =============================================================================
# Code Server (via Coder Registry Module)
# =============================================================================

module "code_server" {
  source  = "registry.coder.com/modules/code-server/coder"
  version = ">= 1.0.0"
  
  agent_id   = var.agent_id
  folder     = var.folder
  order      = var.order
  settings   = var.settings
  extensions = var.extensions
}

# =============================================================================
# Outputs
# =============================================================================

# Note: The registry module doesn't expose an ID output
# If you need to reference this, use depends_on in other resources
