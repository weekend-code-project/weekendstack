# =============================================================================
# Traefik Parameters (Vite Template Override)
# =============================================================================
# OVERRIDE NOTE: Traefik auth disabled but preview button enabled

# No password protection parameter - auth disabled
# Preview button provided via simple coder_app resource

# Preview button for Vite dev server
resource "coder_app" "preview" {
  agent_id     = module.agent.agent_id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/icon/coder.svg"
  url          = "https://${lower(data.coder_workspace.me.name)}.${var.base_domain}"
  share        = "owner"
  subdomain    = false
  
  healthcheck {
    url       = "https://${lower(data.coder_workspace.me.name)}.${var.base_domain}"
    interval  = 5
    threshold = 6
  }
}
