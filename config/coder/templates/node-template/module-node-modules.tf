module "node_modules_persistence" {
  source             = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-modules-persistence?ref=v0.1.1"
  agent_id           = coder_agent.main.id
  node_modules_paths = data.coder_parameter.node_modules_paths.value
  workspace_folder   = "/home/coder/workspace"
  persist_folder     = "/home/coder/.persist"
}
