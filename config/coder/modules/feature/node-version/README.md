# Node Version Module

Installs and selects a Node.js version using a configurable strategy.

## Strategies

| Strategy | Description | Best For |
|----------|-------------|----------|
| `system` | NodeSource apt repo (no version manager) | Simple, fast setup |
| `nvm` | Node Version Manager (default) | Most compatible |
| `volta` | Volta (Rust-based) | Fast, hermetic |
| `fnm` | Fast Node Manager | Fast, Rust-based |
| `n` | Simple `n` package | Minimal overhead |

## Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_id` | string | required | Coder agent ID |
| `install_strategy` | string | `"nvm"` | Install strategy |
| `node_version` | string | `"lts"` | Node.js version (e.g., `lts`, `22`, `20`, `18`) |
| `package_manager` | string | `"npm"` | Package manager: `npm`, `pnpm`, `yarn` |

## Outputs

| Output | Description |
|--------|-------------|
| `install_strategy` | Strategy used |
| `node_version` | Requested version |
| `package_manager` | Configured package manager |

## Usage

```hcl
module "node_version" {
  source = "./modules/feature/node-version"

  agent_id         = coder_agent.main.id
  install_strategy = "nvm"
  node_version     = data.coder_parameter.node_version.value
  package_manager  = "npm"
}
```
