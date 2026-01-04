# Node.js Tooling Module

This module installs Node.js, package managers, and common tooling using NVM.

## Parameters

- `node_version`: Node.js version to install (e.g., 'lts', '20', '18')
- `package_manager`: Package manager to install (npm, pnpm, yarn)
- `enable_typescript`: Boolean to install typescript globally
- `enable_eslint`: Boolean to install eslint globally

## Usage

```hcl
module "node_tooling" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/node-tooling-module?ref=PLACEHOLDER"
  
  node_version      = "lts"
  package_manager   = "npm"
  enable_typescript = true
  enable_eslint     = true
}
```
