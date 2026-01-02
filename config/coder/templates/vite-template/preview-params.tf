# =============================================================================
# Preview Link Parameters
# =============================================================================
# Provides preview button with selectable modes: internal (Coder proxy),
# traefik (external subdomain), or custom URL

# Parameter: Preview Link Mode
data "coder_parameter" "preview_link_mode" {
  name         = "preview_link_mode"
  display_name = "Preview Mode"
  description  = "How to access your Vite dev server"
  type         = "string"
  default      = "traefik"
  mutable      = true
  order        = 25
  
  option {
    name  = "External (Traefik)"
    value = "traefik"
    icon  = "/icon/globe.svg"
  }
  
  option {
    name  = "Internal (Coder Proxy)"
    value = "internal"
    icon  = "/icon/coder.svg"
  }
}

# Module: Preview Link (always loaded, mode determines which button shows)
module "preview_link" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/preview-link-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = lower(data.coder_workspace.me.name)
  workspace_owner       = data.coder_workspace_owner.me.name
  base_domain           = var.base_domain
  exposed_port          = "8080"
  workspace_start_count = data.coder_workspace.me.start_count
  preview_mode          = data.coder_parameter.preview_link_mode.value
  custom_preview_url    = ""
}
