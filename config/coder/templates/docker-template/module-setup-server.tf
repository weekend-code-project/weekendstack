# =============================================================================
# MODULE: Setup Server
# =============================================================================
# Configures and starts the workspace server (static site or custom)
# =============================================================================

# Parameters
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

# Locals
locals {
  exposed_ports_raw = try(
    data.coder_parameter.exposed_ports[0].value,
    jsonencode(["8080"])
  )

  exposed_ports_list = try(
    jsondecode(local.exposed_ports_raw),
    tolist(local.exposed_ports_raw),
    [tostring(local.exposed_ports_raw)]
  )
}

# Module
module "setup_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.0"
  
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  auto_generate_html    = data.coder_parameter.auto_generate_html.value
  exposed_ports_list    = local.exposed_ports_list
  startup_command       = try(data.coder_parameter.startup_command[0].value, "")
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  workspace_url         = local.preview_url  # Now uses dynamic URL from preview-link module
}
