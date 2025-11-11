# =============================================================================
# Setup Server Parameters
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Integrates with the setup-server module.

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "num_ports" {
  name         = "num_ports"
  display_name = "Number of Ports"
  description  = "Number of ports to expose (each gets auto-assigned external port)"
  type         = "number"
  form_type    = "slider"
  default      = 1
  mutable      = true
  order        = 20
  
  validation {
    min = 1
    max = 10
  }
}

data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Auto Start Server"
  description  = "Automatically start a default server (serves static HTML page)"
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 21
}

# Disabled when auto server is enabled
data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Custom command to run at startup (leave empty for no command)"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
  
  styling = jsonencode({
    disabled = data.coder_parameter.auto_generate_html.value
  })
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
  
  # Determine if we should set up the server
  auto_generate_html = data.coder_parameter.auto_generate_html.value
  startup_command    = data.coder_parameter.startup_command.value
  has_server_config  = local.auto_generate_html || local.startup_command != ""
}

# =============================================================================
# Module Integration
# =============================================================================

# Call the setup-server module with test-template specific defaults
module "setup_server" {
  count = local.has_server_config ? 1 : 0
  
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server?ref=PLACEHOLDER"
  
  # Workspace identity for deterministic port generation
  workspace_id = data.coder_workspace.me.id
  
  # Port configuration
  exposed_ports_list = local.exposed_ports_list
  
  # Test template uses Python as default server
  default_server_command = "python3 -m http.server $PORT --bind 0.0.0.0"
  server_name            = "Python HTTP Server"
  server_log_file        = "/tmp/http-server.log"
  server_pid_file        = "/tmp/http-server.pid"
  
  # Python is pre-installed in base image, no setup needed
  pre_server_setup = ""
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  host_ip         = var.host_ip
  
  # Parameters from above
  auto_generate_html = tostring(local.auto_generate_html)
  startup_command    = local.startup_command
}
