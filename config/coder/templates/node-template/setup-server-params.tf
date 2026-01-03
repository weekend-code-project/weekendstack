# =============================================================================
# Setup Server Parameters (Node.js Template Override)
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Integrates with the setup-server module.
#
# OVERRIDE NOTE: This file overrides the shared setup-server-params.tf
# to provide a Node.js-specific default startup command.

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "use_custom_command" {
  name         = "use_custom_command"
  display_name = "Use Custom Server Command"
  description  = "Enable custom server startup command (disables default static server)"
  type         = "bool"
  form_type    = "switch"
  default      = "false"
  mutable      = true
  order        = 20
}

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Server Startup Command"
  description  = "Custom command to run server at startup (default: npx http-server)"
  type         = "string"
  default      = "npx -y http-server -p 8080"
  mutable      = true
  order        = 21
  
  styling = jsonencode({
    disabled = !data.coder_parameter.use_custom_command.value
  })
}

data "coder_parameter" "num_ports" {
  name         = "num_ports"
  display_name = "Number of Ports"
  description  = "Number of ports to expose (each gets auto-assigned external port)"
  type         = "number"
  form_type    = "slider"
  default      = 1
  mutable      = true
  order        = 22
  
  validation {
    min = 1
    max = 10
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Always use the user-specified number of ports
  num_ports_value = data.coder_parameter.num_ports.value
  
  # Generate list of internal ports: [8080, 8081, 8082, ...]
  exposed_ports_list = [
    for i in range(local.num_ports_value) : tostring(8080 + i)
  ]
  
  # Determine server configuration
  use_custom_command = data.coder_parameter.use_custom_command.value
  
  # Robust default command that ensures nvm is loaded and uses selected package manager
  nvm_load           = "export NVM_DIR=\"$HOME/.nvm\"; [ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\""
  pkg_mgr            = data.coder_parameter.node_package_manager.value
  default_command    = "${local.nvm_load}; nvm use default >/dev/null 2>&1; http-server -p 8080 -a 0.0.0.0"
  
  custom_command     = trimspace(data.coder_parameter.startup_command.value)

  # Always regenerate the landing page and server command
  auto_generate_html = true
  startup_command    = local.use_custom_command ? coalesce(local.custom_command != "" ? local.custom_command : null, local.default_command) : local.default_command
  has_server_config  = true  # Always run server (either default or custom)
}

# =============================================================================
# Module Integration
# =============================================================================

# Call the setup-server module - always enabled if startup command is set
module "setup_server" {
  count = local.has_server_config ? 1 : 0
  
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server-module?ref=PLACEHOLDER"
  
  # Workspace identity for deterministic port generation
  workspace_id = data.coder_workspace.me.id
  agent_id     = module.agent.agent_id
  
  # Port configuration
  exposed_ports_list = local.exposed_ports_list
  
  # Use whatever command the user specified (defaults to Node http-server)
  default_server_command = local.startup_command
  server_name            = "Node Server"
  server_log_file        = "/tmp/server.log"
  server_pid_file        = "/tmp/server.pid"
  
  # Custom instructions for Node.js
  server_stop_command    = "pkill -f http-server"
  server_restart_command = "http-server -p $PORT -a 0.0.0.0"
  
  # Node is installed by node-tooling, no extra setup needed here
  pre_server_setup = ""
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  host_ip         = var.host_ip
  
  # Pass through the auto-generate toggle value
  auto_generate_html = tostring(local.auto_generate_html)
  startup_command    = local.startup_command
}
