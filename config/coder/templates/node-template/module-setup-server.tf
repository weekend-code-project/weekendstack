# =============================================================================
# Node Template - Setup Server (Local)
# =============================================================================
## Node Template Setup Server Wrapper (Express variant)
## Provides identical parameters & UX as shared setup-server, sourcing implementation
## from git module setup-server-node (Express-based).

data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Serve Static Site"
  description  = "Toggle on to scaffold a static welcome page."
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
  description  = "Ports to expose."
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["8080"])  # Match shared module default
  mutable      = true
  order        = 21
}

data "coder_parameter" "startup_command" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run at startup."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
}

locals {
  exposed_ports_raw  = try(data.coder_parameter.exposed_ports[0].value, jsonencode(["8080"]))
  exposed_ports_list = try(jsondecode(local.exposed_ports_raw), tolist(local.exposed_ports_raw), [tostring(local.exposed_ports_raw)])
}

# Preview app matching the first exposed port
module "setup_server_node" {
  source                = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server-node?ref=v0.1.4"
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  auto_generate_html    = data.coder_parameter.auto_generate_html.value
  exposed_ports_list    = local.exposed_ports_list
  startup_command       = try(data.coder_parameter.startup_command[0].value, "")
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  workspace_url         = "http://localhost:${element(local.exposed_ports_list, 0)}"
}

# Node-based setup server script
output "setup_server_script" {
  value       = module.setup_server_node.setup_server_script
  description = "Express-based setup server script (from git module)"
}
