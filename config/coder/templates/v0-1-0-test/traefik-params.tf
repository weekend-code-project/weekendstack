# =============================================================================
# Traefik Parameters
# =============================================================================
# Required by git-modules/traefik-auth and traefik-routing modules

# Toggle: Make Public (when true, workspace is public and no auth required)
data "coder_parameter" "make_public" {
  name         = "make_public"
  display_name = "Make Public"
  description  = "Make the workspace url publicly accessible without a password."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 10
}

# Display the password as a workspace parameter (conditionally shown with count)
data "coder_parameter" "workspace_secret" {
  # Only show the secret when the workspace is private (make_public = false)
  count        = data.coder_parameter.make_public.value ? 0 : 1
  
  name         = "workspace_secret"
  display_name = "Private Password"
  description  = "Enter a password to protect the workspace URL."
  type         = "string"
  default      = ""
  mutable      = true
  form_type    = "input"
  order        = 11
  
  validation {
    regex = "^.+$"
    error = "Suggested random password: ${random_password.workspace_secret.result}"
  }
}
