module "node_tooling" {
  source          = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-tooling?ref=v0.1.0"
  enable_typescript = data.coder_parameter.enable_typescript.value
  enable_eslint     = data.coder_parameter.enable_eslint.value
  package_manager   = data.coder_parameter.node_package_manager.value
}
