# =============================================================================
# Traefik Routing Parameters
# =============================================================================
# Parameters for Traefik routing and preview configuration

# Order 30: Preview mode selection
data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  description  = "How to access your workspace"
  type         = "string"
  default      = "traefik"
  mutable      = true
  order        = 30
  
  option {
    name  = "External URL (Traefik)"
    value = "traefik"
    icon  = "/icon/globe.svg"
  }
  option {
    name  = "Internal Proxy (Coder)"
    value = "internal"
    icon  = "/icon/coder.svg"
  }
}

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
  preview_mode = data.coder_parameter.preview_mode.value
  
  # Determine if workspace should be public based on whether a password is provided
  # If workspace_secret parameter is empty, workspace is public (no auth)
  make_public = data.coder_parameter.workspace_secret.value == ""
  
  # Use provided password or fall back to auto-generated one (same pattern as SSH)
  resolved_workspace_secret = data.coder_parameter.workspace_secret.value != "" ? data.coder_parameter.workspace_secret.value : random_password.workspace_secret.result
  
  # Enable Traefik routing (always create module, it handles preview button for both modes)
  enable_traefik = true
  
  # Get auth setup script from module output (only when module is enabled)
  traefik_auth_setup_script = try(module.traefik[0].auth_setup_script, "")
}

# Module call for Traefik routing
module "traefik" {
  count  = local.enable_traefik ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = local.actual_base_domain
  exposed_port     = element(local.exposed_ports_list, 0)
  preview_mode     = local.preview_mode
  make_public      = local.make_public
  workspace_secret = local.resolved_workspace_secret
}
