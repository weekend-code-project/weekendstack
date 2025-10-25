# =============================================================================
# MODULE: VS Code Server
# =============================================================================
# DESCRIPTION:
#   Configures VS Code Server (code-server) as the web-based IDE for the workspace.
#   Uses the official Coder registry module.
#
# DEPENDENCIES:
#   - data.coder_workspace.me
#   - coder_agent.main
#
# OUTPUTS:
#   - module.code-server: The VS Code server module instance
#
# USAGE:
#   Automatically provides a "VS Code" button in the Coder UI that opens
#   the web-based IDE when clicked.
#
# CONFIGURATION:
#   - Opens to /home/coder/workspace directory
#   - Custom settings for font size, theme, etc.
#   - No startup editor (goes straight to file explorer)
#
# =============================================================================

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/modules/code-server/coder"
  version = ">= 1.0.0"
  
  folder   = "/home/coder/workspace"
  agent_id = coder_agent.main.id
  order    = 1

  settings = {
    "editor.tabSize"               = 2
    "workbench.colorTheme"         = "Default Dark+"
    "editor.fontSize"              = 18
    "terminal.integrated.fontSize" = 18
    "workbench.startupEditor"      = "none"
    "workbench.iconTheme"          = "let-icons"
  }

  extensions = []
}
