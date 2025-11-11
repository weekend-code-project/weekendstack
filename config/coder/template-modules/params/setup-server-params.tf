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

data "coder_parameter" "exposed_ports" {
  count        = !data.coder_parameter.auto_generate_html.value ? 1 : 0
  name         = "exposed_ports"
  display_name = "Exposed Ports"
  description  = "Comma-separated ports to expose (e.g., 8080,3000,5000)"
  type         = "string"
  default      = "8080"
  mutable      = true
  order        = 21
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
  # Parse exposed ports from comma-separated string to list
  # When auto_generate_html is true, use default port 8080
  # When false, use the conditional parameter value
  exposed_ports_input = data.coder_parameter.auto_generate_html.value ? "8080" : try(data.coder_parameter.exposed_ports[0].value, "8080")
  exposed_ports_list  = [for p in split(",", local.exposed_ports_input) : trimspace(p)]
  
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
