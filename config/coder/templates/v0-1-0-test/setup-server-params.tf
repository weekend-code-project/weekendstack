# =============================================================================
# Setup Server Parameters
# =============================================================================
# Required by git-modules/setup-server module
# Copy this file to use setup server integration in your template

# Parameter: Auto-generate HTML
data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Serve Static Site"
  description  = "Toggle on to scaffold a static welcome page and run the static site server. Turn off to customize your server ports and startup command."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 20
}

# Parameter: Expose custom ports (only when running your own server)
data "coder_parameter" "exposed_ports" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "exposed_ports"
  display_name = "Exposed Ports"
  description  = "Add one or more ports to expose when running your own server. The first port is routed through Traefik."
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["8080"])
  mutable      = true
  order        = 21
}

# Parameter: Startup Command
data "coder_parameter" "startup_command" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run at workspace startup (for example: npm run dev)."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
}

# Compute exposed ports list (needed for the module)
locals {
  # Determine exposed ports even when the parameter is hidden (auto-generate HTML)
  exposed_ports_raw = try(
    data.coder_parameter.exposed_ports[0].value,
    jsonencode(["8080"])
  )

  # Robustly derive a list of ports regardless of how the provider returns the value
  exposed_ports_list = try(
    jsondecode(local.exposed_ports_raw),
    tolist(local.exposed_ports_raw),
    [tostring(local.exposed_ports_raw)]
  )
}
