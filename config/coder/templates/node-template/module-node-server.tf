data "coder_parameter" "node_ports" {
  name         = "node_ports"
  display_name = "Node Ports"
  description  = "Ports to expose for the Node server"
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["3000"])
  order        = 105
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
}
