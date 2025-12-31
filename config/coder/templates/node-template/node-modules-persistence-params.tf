# =============================================================================
# Node Modules Persistence Parameters
# =============================================================================
# This file defines parameters for managing persistent node_modules directories
# across workspace rebuilds with automatic dependency installation.

data "coder_parameter" "node_modules_paths" {
  name         = "node_modules_paths"
  display_name = "Node Modules Paths"
  description  = "Comma-separated paths for node_modules directories (e.g., node_modules,backend/node_modules,frontend/node_modules). Leave empty to disable."
  type         = "string"
  default      = "node_modules"
  mutable      = true
  order        = 105
}

# Module: node-modules-persistence
# Manages persistent node_modules with automatic dependency installation
module "node_modules_persistence" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/node-modules-persistence-module?ref=PLACEHOLDER"
  
  agent_id          = module.agent.agent_id
  node_modules_paths = data.coder_parameter.node_modules_paths.value
  workspace_folder  = "/home/coder/workspace"
  persist_folder    = "/home/coder/.persist"
}
