# =============================================================================
# Traefik Routing Parameters
# =============================================================================
# Provides Traefik routing labels and preview buttons
# Docker template is always public (no auth)

# Parameter: Preview Mode
data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  description  = "How to access your workspace"
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

# Locals for Traefik module
locals {
  traefik_auth_setup_script = module.traefik.auth_setup_script
}

# Traefik Routing Module (handles routing + preview, no auth for docker template)
module "traefik" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = local.actual_base_domain
  exposed_port     = "8080"
  preview_mode     = data.coder_parameter.preview_mode.value
  workspace_secret = ""  # Docker template is always public, no auth
}
