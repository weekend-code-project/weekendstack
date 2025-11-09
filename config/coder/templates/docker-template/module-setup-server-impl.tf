# =============================================================================
# Setup Server Module (Python) - Local to Docker Template
# =============================================================================
# This module configures the shared setup-server git module with Python-specific
# parameters. The actual server logic is in the shared git module.

# Resolve startup command at Terraform time
locals {
  startup_cmd_value = try(data.coder_parameter.startup_command.value, "")
}

# Call the shared setup-server git module with Python-specific configuration
module "setup_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.1"
  
  # Port configuration
  exposed_ports_list = local.exposed_ports_list
  
  # Python-specific configuration
  default_server_command = "python3 -m http.server $PORT --bind 0.0.0.0"
  server_name            = "Python 3 HTTP Server"
  server_log_file        = "/tmp/http-server.log"
  server_pid_file        = "/tmp/http-server.pid"
  
  # HTML content for static site
  html_status_message = "Python HTTP server is running!"
  html_server_info    = "Python 3 HTTP server on port $PORT"
  html_instructions   = <<-INSTRUCTIONS
    # Edit the current page
    vi index.html
    
    # Or create your own site
    mkdir -p mysite
    cd mysite
    echo "<h1>Hello World</h1>" > index.html
    
    # Restart the server
    pkill -f "python3 -m http.server"
    python3 -m http.server $PORT
  INSTRUCTIONS
  
  # No pre-setup needed for Python (it's already installed)
  pre_server_setup = ""
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  workspace_owner = data.coder_workspace_owner.me.name
  
  # Parameters from shared template modules
  auto_generate_html = data.coder_parameter.auto_generate_html.value
  startup_command    = local.startup_cmd_value
}

# Export the script for use in agent module
locals {
  setup_server_script = module.setup_server.setup_server_script
}