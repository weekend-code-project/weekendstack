# Node Tooling Module

Installs optional global Node.js packages and configures cache directories.

## Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_id` | string | required | Coder agent ID |
| `enable_typescript` | bool | `false` | Install TypeScript globally |
| `enable_eslint` | bool | `false` | Install ESLint globally |
| `enable_http_server` | bool | `false` | Install http-server globally |
| `extra_packages` | string | `""` | Additional packages (space-separated) |
| `package_manager` | string | `"npm"` | Package manager: `npm`, `pnpm`, `yarn` |

## Outputs

| Output | Description |
|--------|-------------|
| `packages_installed` | List of packages configured for installation |

## Usage

```hcl
module "node_tooling" {
  source = "./modules/feature/node-tooling"

  agent_id          = coder_agent.main.id
  enable_typescript = true
  package_manager   = "npm"
}
```
