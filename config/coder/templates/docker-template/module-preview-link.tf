# =============================================================================
# MODULE: Preview Link Configuration
# =============================================================================
# DESCRIPTION:
#   Configures the preview app URL with 3 modes: internal, traefik, or custom.
#
# MODES:
#   1. Internal (default) - Uses Coder's built-in proxy
#      URL: https://coder.domain/@user/workspace.main/apps/preview/
#
#   2. Traefik - Uses Traefik routing with workspace subdomain
#      URL: https://workspace-name.weekendcodeproject.dev/
#      Requires Traefik routing to be working
#
#   3. Custom - User provides their own URL
#      Shows text input field for custom URL
# =============================================================================

# =============================================================================
# Parameters
# =============================================================================

# Mode selector (radio buttons)
data "coder_parameter" "preview_link_mode" {
  name         = "preview_link_mode"
  display_name = "Preview Link Mode"
  description  = "Choose how the preview app URL is generated."
  type         = "string"
  default      = "internal"
  mutable      = true
  order        = 23
  
  option {
    name  = "Internal (Coder Proxy)"
    value = "internal"
    icon  = "/icon/coder.svg"
  }
  
  option {
    name  = "Traefik (External Subdomain)"
    value = "traefik"
    icon  = "/icon/globe.svg"
  }
  
  option {
    name  = "Custom URL"
    value = "custom"
    icon  = "/icon/link.svg"
  }
}

# Custom URL input (only shown when mode=custom)
data "coder_parameter" "custom_preview_url" {
  count        = data.coder_parameter.preview_link_mode.value == "custom" ? 1 : 0
  name         = "custom_preview_url"
  display_name = "Custom Preview URL"
  description  = "Enter your custom preview URL (e.g., https://myapp.example.com)"
  type         = "string"
  default      = ""
  mutable      = true
  form_type    = "input"
  order        = 24
  
  validation {
    regex = "^https?://.+"
    error = "URL must start with http:// or https://"
  }
}

# =============================================================================
# Preview URL Logic
# =============================================================================

locals {
  # Determine the preview URL based on mode
  preview_url = (
    data.coder_parameter.preview_link_mode.value == "traefik" ? local.workspace_url :
    data.coder_parameter.preview_link_mode.value == "custom" ? try(data.coder_parameter.custom_preview_url[0].value, "") :
    "http://localhost:${element(local.exposed_ports_list, 0)}"  # internal (default)
  )
}
