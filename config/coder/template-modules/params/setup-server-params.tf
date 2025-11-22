# =============================================================================
# Setup Server Parameters
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Integrates with the setup-server module.

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
  description  = "Custom command to run server at startup"
  type         = "string"
  default      = "python3 -m http.server 8080 --bind 0.0.0.0"
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
  default_command    = "python3 -m http.server 8080 --bind 0.0.0.0"
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
  
  # Use whatever command the user specified (defaults to Python server)
  default_server_command = local.startup_command
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
  startup_command    = local.startup_command
}
