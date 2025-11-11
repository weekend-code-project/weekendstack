# =============================================================================
# Setup Server Parameters
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Integrates with the setup-server module.

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Serve Static Site"
  description  = "Automatically create and serve a welcome page"
  type         = "bool"
  default      = true
  mutable      = true
  order        = 20
}

# Always visible - disabled when not in use
data "coder_parameter" "num_ports" {
  name         = "num_ports"
  display_name = "Number of Ports"
  description  = "Number of ports to expose (only used when Static Site is disabled)"
  type         = "number"
  form_type    = "slider"
  default      = 1
  mutable      = true
  order        = 21
  
  validation {
    min = 1
    max = 10
  }
  
  option {
    name  = "Disabled when Static Site is enabled"
    value = "0"
    icon  = "/emojis/1f6ab.png"
  }
}

# Always visible - disabled when not in use
data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Custom command to run at startup (only used when Static Site is disabled, leave empty for default)"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
  
  option {
    name  = "Disabled when Static Site is enabled"
    value = ""
    icon  = "/emojis/1f6ab.png"
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # When auto_generate_html is true, use single port 8080
  # When false, generate ports based on num_ports parameter (starting at 8080)
  num_ports_value = data.coder_parameter.auto_generate_html.value ? 1 : data.coder_parameter.num_ports.value
  
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
