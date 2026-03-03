# Node Modules Persistence Module

Persists `node_modules` directories across workspace restarts using symlinks to a dedicated Docker volume, keeping the workspace home volume lean.

## How It Works

1. Creates a separate Docker volume for node_modules storage
2. At startup, symlinks each node_modules path to the persistent volume
3. Detects lock files and runs the correct package manager (`npm ci`, `pnpm install`, `yarn install`)
4. Uses lock-file hash sentinel to skip installs when deps haven't changed

## Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `agent_id` | string | required | Coder agent ID |
| `workspace_name` | string | required | Workspace name (for volume naming) |
| `owner_name` | string | required | Owner name (for volume naming) |
| `workspace_folder` | string | `/home/coder/workspace` | Workspace root path |
| `node_modules_paths` | string | `"node_modules"` | Comma-separated relative paths |
| `enabled` | bool | `false` | Toggle persistence on/off |

## Outputs

| Output | Description |
|--------|-------------|
| `volume_name` | Docker volume name (empty when disabled) |
| `volume_mount_path` | Container path for the persist volume mount |
| `enabled` | Whether persistence is active |

## Usage

```hcl
module "node_modules_persist" {
  source = "./modules/feature/node-modules-persist"

  agent_id           = coder_agent.main.id
  workspace_name     = local.workspace_name
  owner_name         = local.owner_name
  workspace_folder   = local.workspace_folder
  node_modules_paths = "node_modules"
  enabled            = data.coder_parameter.persist_node_modules.value
}

# In the docker_container resource, add this volume conditionally:
dynamic "volumes" {
  for_each = module.node_modules_persist.enabled ? [1] : []
  content {
    volume_name    = module.node_modules_persist.volume_name
    container_path = module.node_modules_persist.volume_mount_path
  }
}
```
