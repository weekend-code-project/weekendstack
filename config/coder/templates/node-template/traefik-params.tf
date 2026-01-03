# =============================================================================
# Traefik Routing Parameters (Node Template Override)
# =============================================================================
# OVERRIDE NOTE: Disables Traefik preview button since we use preview-link-module
# Preview button is provided by preview-params.tf using preview-link-module

# Order 31: Workspace password (optional - if empty, workspace is public)
data "coder_parameter" "workspace_secret" {
  name         = "workspace_secret"
  display_name = "Workspace Password (Optional)"
  description  = "Leave blank for public access, or set a password to require authentication"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 31
  
  validation {
    regex = "^.{0,}$"
    error = "Suggested random password: ${random_password.workspace_secret.result}"
  }
}

# Locals for Traefik module
locals {
  # Pass the workspace_secret parameter value directly to the module
  # Module will determine if auth is needed based on whether password is empty
  workspace_secret_value = data.coder_parameter.workspace_secret.value
  
  # Enable Traefik routing for labels only (no preview button)
  enable_traefik = true
  
  # Get auth setup script from module output (only when module is enabled)
  traefik_auth_setup_script = try(module.traefik[0].auth_setup_script, "")
}

# Module call for Traefik routing (labels only, no preview)
module "traefik" {
  count  = local.enable_traefik ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = local.actual_base_domain
  exposed_port     = element(local.exposed_ports_list, 0)
  preview_mode     = "none"  # Disable preview button from traefik module
  workspace_secret = local.workspace_secret_value
}
