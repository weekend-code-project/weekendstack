# =============================================================================
# MODULE: Workspace Preview App
# =============================================================================
# DESCRIPTION:
#   Creates a Coder app that provides a clickable link to the workspace's
#   external URL via Traefik proxy.
#
# DEPENDENCIES:
#   - coder_agent.main
#   - local.workspace_url (from traefik-routing.tf)
#
# OUTPUTS:
#   - coder_app.preview: App resource with external workspace link
#
# NOTES:
#   - This app appears in the Coder UI dashboard
#   - Opens in external browser (external = true)
#   - URL is automatically generated based on workspace name and domain
#
# =============================================================================

resource "coder_app" "preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Workspace Preview"
  url          = local.workspace_url
  icon         = "/icon/desktop.svg"
  external     = true
}
