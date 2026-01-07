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
  description  = "Command to run server at startup (defaults to Python HTTP server)"
  type         = "string"
  default      = "python3 -m http.server 8080 --bind 0.0.0.0"
  mutable      = true
  order        = 20
}

data "coder_parameter" "generate_html" {
  name         = "generate_html"
  display_name = "Generate Landing Page"
  description  = "Auto-generate index.html if it doesn't exist"
  type         = "bool"
  form_type    = "switch"
  default      = "true"
  mutable      = true
  order        = 21
}

data "coder_parameter" "num_ports" {
  name         = "num_ports"
  display_name = "Number of Ports"
  description  = "Number of ports to expose (8080-8089)"
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
  # Generate list of internal ports: [8080, 8081, 8082, ...]
  num_ports_value = data.coder_parameter.num_ports.value
  exposed_ports_list = [
    for i in range(local.num_ports_value) : tostring(8080 + i)
  ]
  
  # Server configuration
  startup_command    = trimspace(data.coder_parameter.startup_command.value)
  auto_generate_html = data.coder_parameter.generate_html.value
  has_server_config  = local.startup_command != ""  # Only run server if command provided
}

# =============================================================================
# Module Integration
# =============================================================================

# Call the setup-server module (always instantiated, handles empty command internally)
module "setup_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server-module?ref=PLACEHOLDER"
  
  # Workspace identity for deterministic port generation
  workspace_id = data.coder_workspace.me.id
  agent_id     = module.agent.agent_id
  
  # Port configuration
  exposed_ports_list = local.exposed_ports_list
  
  # Server command
  default_server_command = local.startup_command
  server_name            = "Web Server"
  server_log_file        = "/tmp/server.log"
  server_pid_file        = "/tmp/server.pid"
  
  # Python is pre-installed in base image, no setup needed
  pre_server_setup = ""
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  host_ip         = var.host_ip
  
  # HTML generation toggle
  auto_generate_html = tostring(local.auto_generate_html)
  startup_command    = local.startup_command
}
