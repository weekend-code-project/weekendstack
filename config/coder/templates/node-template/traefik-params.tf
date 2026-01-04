# =============================================================================
# Traefik Routing Parameters
# =============================================================================
# Provides Traefik routing labels, authentication, and preview buttons
# This is the ONLY module needed - handles all routing/auth/preview functionality

# Parameter: Preview Mode
data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  description  = "How to access your Node dev server"
  type         = "string"
  default      = "traefik"
  mutable      = true
  order        = 30
  
  option {
    name  = "External (Traefik)"
    value = "traefik"
    icon  = "/icon/desktop.svg"
  }
  
  option {
    name  = "Internal (Coder Proxy)"
    value = "internal"
    icon  = "/icon/coder.svg"
  }
}

# Parameter: Workspace password (optional - if empty, workspace is public)
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
  workspace_secret_value = data.coder_parameter.workspace_secret.value
  traefik_auth_setup_script = module.traefik.auth_setup_script
}

# Traefik Routing Module (handles routing + auth + preview)
module "traefik" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = local.actual_base_domain
  exposed_port     = element(local.exposed_ports_list, 0)
  preview_mode     = data.coder_parameter.preview_mode.value
  workspace_secret = local.workspace_secret_value
}
