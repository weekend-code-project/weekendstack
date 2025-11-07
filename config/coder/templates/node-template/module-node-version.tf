data "coder_parameter" "node_install_strategy" {
  name         = "node_install_strategy"
  display_name = "Node Install Strategy"
  description  = "Choose how Node is managed: system (image), volta, fnm, or n"
  type         = "string"
  default      = "system"
  order        = 100
    option { name = "System (image)" value = "system" }
    option { name = "Volta" value = "volta" }
    option { name = "FNM" value = "fnm" }
    option { name = "n" value = "n" }
}

data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node Version"
  description  = "Select a Node version (e.g., 22, 20, 18, lts)"
  type         = "string"
  default      = "20"
  order        = 101
    option { name = "Latest LTS" value = "lts" }
    option { name = "22.x" value = "22" }
    option { name = "20.x" value = "20" }
    option { name = "18.x" value = "18" }
    option { name = "16.x" value = "16" }
}

data "coder_parameter" "node_package_manager" {
  name         = "node_package_manager"
  display_name = "Package Manager"
  description  = "Preferred package manager"
  type         = "string"
  default      = "npm"
  order        = 102
    option { name = "npm" value = "npm" }
    option { name = "pnpm" value = "pnpm" }
    option { name = "yarn" value = "yarn" }
}

data "coder_parameter" "enable_typescript" {
  name         = "enable_typescript"
  display_name = "Install TypeScript"
  type         = "bool"
  form_type    = "switch"
  default      = true
  order        = 103
}

data "coder_parameter" "enable_eslint" {
  name         = "enable_eslint"
  display_name = "Install ESLint"
  type         = "bool"
  form_type    = "switch"
  default      = true
  order        = 104
}

module "node_version" {
  source           = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-version?ref=v0.1.0"
  install_strategy = data.coder_parameter.node_install_strategy.value
  node_version     = data.coder_parameter.node_version.value
  package_manager  = data.coder_parameter.node_package_manager.value
}
