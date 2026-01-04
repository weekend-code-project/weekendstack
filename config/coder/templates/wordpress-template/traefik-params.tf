# =============================================================================
# Traefik Routing Configuration
# =============================================================================

data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  description  = "How to access your workspace"
  type         = "string"
  default      = "traefik"
  mutable      = false
  order        = 90

  option {
    name  = "External URL (Traefik)"
    value = "traefik"
  }
  option {
    name  = "Internal Proxy (Coder)"
    value = "coder"
  }
}

data "coder_parameter" "workspace_secret" {
  name         = "workspace_secret"
  display_name = "Workspace Password (Optional)"
  description  = "Leave blank for public access, or set a password to require authentication"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 91
}

locals {
  workspace_secret_value    = data.coder_parameter.workspace_secret.value
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
  
  domain           = var.base_domain
  exposed_port     = "80"  # WordPress runs on port 80
  preview_mode     = data.coder_parameter.preview_mode.value
  workspace_secret = local.workspace_secret_value
}
