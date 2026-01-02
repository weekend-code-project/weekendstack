# =============================================================================
# Setup Server Parameters (Vite Template Override)
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Integrates with the setup-server module.
#
# OVERRIDE NOTE: This file overrides the shared setup-server-params.tf
# to provide a Vite-specific default startup command.

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "use_custom_command" {
  name         = "use_custom_command"
  display_name = "Use Custom Server Command"
  description  = "Enable custom server startup command (disables default static server)"
  type         = "bool"
  form_type    = "switch"
  default      = "true"
  mutable      = true
  order        = 20
}

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Server Startup Command"
  description  = "Custom command to run server at startup (default runs Vite with workspace config)"
  type         = "string"
  default      = "npx vite --config vite.config.workspace.js"
  mutable      = true
  order        = 21
  
  styling = jsonencode({
    disabled = !data.coder_parameter.use_custom_command.value
  })
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Single exposed port for Vite
  exposed_ports_list = ["8080"]
  
  # Determine server configuration
  use_custom_command = data.coder_parameter.use_custom_command.value
  
  # Construct the workspace URL for Vite's allowed hosts  
  workspace_domain = "${lower(data.coder_workspace.me.name)}.${var.base_domain}"
  
  # No pre-server setup - keep user's vite.config.ts untouched (non-destructive)
  vite_config_override = ""
  
  # Robust default command that ensures nvm is loaded
  nvm_load           = "export NVM_DIR=\"$HOME/.nvm\"; [ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"; nvm use default >/dev/null 2>&1"
  # Use npm run dev to respect project's package.json scripts
  default_command    = "npm run dev -- --host 0.0.0.0"
  
  custom_command     = trimspace(data.coder_parameter.startup_command.value)

  # Disable auto HTML generation for Vite projects - Vite serves its own index.html
  auto_generate_html = false
  # Prefix any command with nvm loading
  startup_command    = local.use_custom_command ? "${local.nvm_load}; ${coalesce(local.custom_command != "" ? local.custom_command : null, local.default_command)}" : "${local.nvm_load}; ${local.default_command}"
  has_server_config  = true  # Always run server (either default or custom)
}

# =============================================================================
# Module Integration
# =============================================================================

# Call the setup-server module - DISABLED for vite-template (we handle startup in agent script)
module "setup_server" {
  count = 0  # Disabled - startup handled directly in agent-params.tf
  
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server-module?ref=PLACEHOLDER"
  
  # Workspace identity for deterministic port generation
  workspace_id = data.coder_workspace.me.id
  agent_id     = module.agent.agent_id
  
  # Port configuration
  exposed_ports_list = local.exposed_ports_list
  
  # Use whatever command the user specified (defaults to Vite dev server)
  default_server_command = local.startup_command
  server_name            = "Vite Dev Server"
  server_log_file        = "/tmp/server.log"
  server_pid_file        = "/tmp/server.pid"
  
  # Custom instructions for Vite
  server_stop_command    = "pkill -f vite"
  server_restart_command = "npx vite --port=$PORT --host 0.0.0.0"
  
  # Create vite config override before starting server
  pre_server_setup = local.vite_config_override
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  host_ip         = var.host_ip
  
  # Pass through the auto-generate toggle value
  auto_generate_html = tostring(local.auto_generate_html)
  startup_command    = local.startup_command
}
