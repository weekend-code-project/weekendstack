# =============================================================================
# Traefik Parameters - WordPress Override
# =============================================================================

data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  description  = "How to handle preview/routing"
  type         = "string"
  default      = "traefik"
  mutable      = true
  order        = 150
  
  option {
    name  = "Traefik (Reverse Proxy)"
    value = "traefik"
  }
  option {
    name  = "Direct Port"
    value = "port"
  }
  option {
    name  = "Disabled"
    value = "none"
  }
}

# Workspace secret for password protection
data "coder_parameter" "workspace_secret" {
  name         = "workspace_secret"
  display_name = "Workspace Password (Optional)"
  description  = "Password for accessing workspace via Traefik. Leave empty to use auto-generated password."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 151
}

# Local values for Traefik configuration
locals {
  preview_mode            = data.coder_parameter.preview_mode.value
  enable_traefik          = local.preview_mode == "traefik"
  workspace_secret_value  = data.coder_parameter.workspace_secret.value != "" ? data.coder_parameter.workspace_secret.value : random_password.workspace_secret.result
}

# Module: traefik (Reverse proxy routing)
module "traefik" {
  count  = local.enable_traefik ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing-module?ref=feature/services-cleanup"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = local.actual_base_domain
  exposed_port     = 80  # WordPress runs on port 80 inside container
  preview_mode     = local.preview_mode
  workspace_secret = local.workspace_secret_value
}
