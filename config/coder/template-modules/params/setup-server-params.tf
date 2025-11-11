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

data "coder_parameter" "num_ports" {
  count        = !data.coder_parameter.auto_generate_html.value ? 1 : 0
  name         = "num_ports"
  display_name = "Number of Ports"
  description  = "Number of ports to expose (each gets auto-assigned external port)"
  type         = "number"
  form_type    = "slider"
  default      = 1
  mutable      = true
  order        = 21
  
  option {
    name  = "1 Port"
    value = 1
  }
  option {
    name  = "2 Ports"
    value = 2
  }
  option {
    name  = "3 Ports"
    value = 3
  }
  option {
    name  = "4 Ports"
    value = 4
  }
  option {
    name  = "5 Ports"
    value = 5
  }
  option {
    name  = "6 Ports"
    value = 6
  }
  option {
    name  = "7 Ports"
    value = 7
  }
  option {
    name  = "8 Ports"
    value = 8
  }
  option {
    name  = "9 Ports"
    value = 9
  }
  option {
    name  = "10 Ports"
    value = 10
  }
}

data "coder_parameter" "startup_command" {
  count        = !data.coder_parameter.auto_generate_html.value ? 1 : 0
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Optional command to run at startup (leave empty for default server)"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # When auto_generate_html is true, use single port 8080
  # When false, generate ports based on num_ports parameter (starting at 8080)
  num_ports_value = data.coder_parameter.auto_generate_html.value ? 1 : try(data.coder_parameter.num_ports[0].value, 1)
  
  # Generate list of internal ports: [8080, 8081, 8082, ...]
  exposed_ports_list = [
    for i in range(local.num_ports_value) : tostring(8080 + i)
  ]
  
  # Determine if we should set up the server
  auto_generate_html = data.coder_parameter.auto_generate_html.value
  startup_command    = try(data.coder_parameter.startup_command[0].value, "")
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
  
  # HTML content for static site
  html_status_message = "Development server is running!"
  html_server_info    = "Python HTTP server on port $PORT"
  html_instructions   = <<-INSTRUCTIONS
    # Edit the current page
    vi index.html
    
    # Or create your own site
    mkdir mysite
    cd mysite
    echo "<h1>Hello World</h1>" > index.html
    
    # Restart the server to serve from a different directory
    pkill -f "python3 -m http.server"
    python3 -m http.server $PORT
  INSTRUCTIONS
  
  # Python is pre-installed in base image, no setup needed
  pre_server_setup = ""
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  workspace_owner = data.coder_workspace_owner.me.name
  host_ip         = var.host_ip
  
  # Parameters from above
  auto_generate_html = tostring(local.auto_generate_html)
  startup_command    = local.startup_command
}
