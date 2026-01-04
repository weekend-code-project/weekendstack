# =============================================================================
# Setup Server Parameters
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Integrates with the setup-server module.

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Server Startup Command"
  description  = "Command to run server at startup (leave empty to disable server)"
  type         = "string"
  default      = "python3 -m http.server 8080 --bind 0.0.0.0"
  mutable      = true
  order        = 21
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
  startup_command    = trimspace(data.coder_parameter.startup_command.value)
  default_command    = "python3 -m http.server 8080 --bind 0.0.0.0"

  # Only enable server if user provided a command
  # If empty, no server runs and no metadata block appears
  auto_generate_html = local.startup_command != ""
  has_server_config  = local.startup_command != ""
  
  # Use provided command, or fall back to default if they want a server but left it empty
  final_command = local.startup_command != "" ? local.startup_command : local.default_command
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
  
  # Use the user's command (or default if somehow empty but has_server_config is true)
  default_server_command = local.final_command
  server_name            = "Static Server"
  server_log_file        = "/tmp/server.log"
  server_pid_file        = "/tmp/server.pid"
  
  # Python is pre-installed in base image, no setup needed
  pre_server_setup = ""
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  host_ip         = var.host_ip
  
  # Pass through the auto-generate toggle value
  auto_generate_html = tostring(local.auto_generate_html)
  startup_command    = local.final_command
}

# =============================================================================
# Outputs
# =============================================================================

output "setup_server_script" {
  description = "Server setup script from setup-server module"
  value       = try(module.setup_server[0].setup_server_script, "")
}
