# =============================================================================
# Preview Link Parameters
# =============================================================================
# Required by git-modules/preview-link module

# Toggle: Use Custom URL
data "coder_parameter" "use_custom_preview_url" {
  name         = "use_custom_preview_url"
  display_name = "Custom Preview URL"
  description  = "Use a custom URL for the preview link instead of the auto-generated Traefik URL."
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 30
}

# Custom Preview URL (only shown when custom URL is enabled)
data "coder_parameter" "custom_preview_url" {
  count        = data.coder_parameter.use_custom_preview_url.value ? 1 : 0
  
  name         = "custom_preview_url"
  display_name = "Custom URL"
  description  = "Custom URL for the external preview link (e.g., 'https://example.com')"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 31
  
  validation {
    regex = "^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$"
    error = "Must be a valid URL starting with http:// or https:// (e.g., 'https://example.com' or 'https://${lower(data.coder_workspace.me.name)}.weekendcodeproject.dev')"
  }
}
