data "coder_parameter" "node_ports" {
  name         = "node_ports"
  display_name = "Node Ports"
  description  = "Ports to expose for the Node server"
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["3000"])
  order        = 105
}

data "coder_parameter" "node_server_mode" {
  name         = "node_server_mode"
  display_name = "Node Server Mode"
  description  = "Choose server behavior: default (dynamic), static (serve index.html), custom (run startup command)"
  type         = "string"
  default      = "default"
  order        = 106
    option { name = "Default" value = "default" }
    option { name = "Static (index.html)" value = "static" }
    option { name = "Custom Command" value = "custom" }
}

data "coder_parameter" "node_startup_command" {
  count        = data.coder_parameter.node_server_mode.value == "custom" ? 1 : 0
  name         = "node_startup_command"
  display_name = "Startup Command"
  description  = "Command to run when server mode is custom"
  type         = "string"
  default      = ""
  order        = 107
}

locals {
  node_ports_raw  = data.coder_parameter.node_ports.value
  node_ports_list = try(jsondecode(local.node_ports_raw), tolist(local.node_ports_raw), [tostring(local.node_ports_raw)])
}

module "node_server" {
  source               = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-server?ref=v0.1.0"
  agent_id             = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  exposed_ports        = local.node_ports_list
  server_mode          = data.coder_parameter.node_server_mode.value
  startup_command      = try(data.coder_parameter.node_startup_command[0].value, "")
}
