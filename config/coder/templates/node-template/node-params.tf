# =============================================================================
# Node.js Template Parameters
# =============================================================================
# This file defines parameters specific to the Node.js template.
# It is overlaid on top of the base template during push.

data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node Version"
  description  = "Select a Node version (e.g., 22, 20, 18, lts)"
  type         = "string"
  default      = "lts"
  order        = 101
  option {
    name  = "Latest LTS"
    value = "lts"
  }
  option {
    name  = "22.x"
    value = "22"
  }
  option {
    name  = "20.x"
    value = "20"
  }
  option {
    name  = "18.x"
    value = "18"
  }
}

data "coder_parameter" "node_package_manager" {
  name         = "node_package_manager"
  display_name = "Package Manager"
  description  = "Preferred package manager"
  type         = "string"
  default      = "npm"
  order        = 102
  option {
    name  = "npm"
    value = "npm"
  }
  option {
    name  = "pnpm"
    value = "pnpm"
  }
  option {
    name  = "yarn"
    value = "yarn"
  }
}



# Module: node-tooling
# Installs Node.js, package managers, and tooling
module "node_tooling" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/node-tooling-module?ref=PLACEHOLDER"
  
  node_version       = data.coder_parameter.node_version.value
  package_manager    = data.coder_parameter.node_package_manager.value
  enable_typescript  = false  # Handled by project package.json
  enable_eslint      = false  # Handled by project package.json
}
