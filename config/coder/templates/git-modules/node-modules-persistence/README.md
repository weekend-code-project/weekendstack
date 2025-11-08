# Node Modules Persistence Module

This module provides intelligent persistence and automatic installation for Node.js dependencies in Coder workspaces.

## Features

- **Persistent Storage**: Bind mounts `node_modules` directories to persistent volumes outside the workspace
- **Automatic Installation**: Detects `package.json` and automatically runs the appropriate package manager
- **Smart Caching**: Only reinstalls when lock files change (hash-based detection)
- **Multi-Path Support**: Can handle multiple `node_modules` directories (monorepos, nested projects)
- **Package Manager Detection**: Automatically uses pnpm, yarn, or npm based on lock files
- **Race Condition Prevention**: Uses file locking to prevent concurrent installs
- **Container Restart Safe**: Persists dependencies across container restarts

## Usage

### Basic Example

```hcl
module "node_modules" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-modules-persistence?ref=v0.1.1"
  
  agent_id           = coder_agent.main.id
  node_modules_paths = "node_modules"
}

resource "coder_agent" "main" {
  # ... other config ...
  
  startup_script = <<-EOT
    ${module.node_modules.init_script}
  EOT
  
  env = merge(
    module.node_modules.env,
    {
      # ... other env vars ...
    }
  )
}
```

### Monorepo Example

```hcl
module "node_modules" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-modules-persistence?ref=v0.1.1"
  
  agent_id           = coder_agent.main.id
  node_modules_paths = "node_modules,backend/node_modules,frontend/node_modules"
  workspace_folder   = "/home/coder/workspace"
}
```

### With Template Parameter

```hcl
data "coder_parameter" "node_modules_paths" {
  name        = "Node Modules Paths"
  description = "Comma-separated paths (relative to workspace folder). Example: node_modules,backend/node_modules"
  type        = "string"
  default     = "node_modules"
  mutable     = true
}

module "node_modules" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/node-modules-persistence?ref=v0.1.1"
  
  agent_id           = coder_agent.main.id
  node_modules_paths = data.coder_parameter.node_modules_paths.value
}
```

## How It Works

### 1. Bind Mounting

Each `node_modules` path is bind mounted to a persistent location:
- Source: `/home/coder/.persist/node_modules/<safe_name>`
- Target: `/home/coder/workspace/<your_path>/node_modules`

The safe name is the path with slashes replaced by underscores (e.g., `backend/node_modules` → `backend_node_modules`)

### 2. Dependency Installation

For each path, the module:
1. Looks for `package.json` in the parent directory
2. Calculates a hash of all lock files (pnpm-lock.yaml, yarn.lock, package-lock.json)
3. Compares with stored hash in `.deps_ready` sentinel file
4. If changed or first run:
   - Detects package manager from lock files
   - Runs appropriate install command
   - Updates sentinel with new hash
5. If unchanged: skips installation

### 3. Package Manager Detection

Priority order:
1. **pnpm**: If `pnpm` command exists and `pnpm-lock.yaml` found
2. **yarn**: If `yarn` command exists and `yarn.lock` found  
3. **npm ci**: If `package-lock.json` exists
4. **npm install**: Fallback if no lock file

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `agent_id` | string | (required) | The ID of a Coder agent |
| `node_modules_paths` | string | `"node_modules"` | Comma-separated relative paths |
| `workspace_folder` | string | `"/home/coder/workspace"` | Path to workspace folder |
| `persist_folder` | string | `"/home/coder/.persist"` | Path to persistence folder |

## Outputs

| Name | Description |
|------|-------------|
| `init_script` | Shell script to include in agent startup |
| `env` | Environment variables to merge into agent |

## Benefits

### Fast Container Restarts
Dependencies persist across container restarts, so you don't reinstall on every workspace start.

### Workspace File System Isolation
`node_modules` directories don't clutter your workspace folder or cause sync issues with bind mounts.

### Bandwidth Efficient
Only downloads packages when lock files change, not on every startup.

### Monorepo Support
Can handle multiple package directories in a single workspace.

## Notes

- Requires `sudo` privileges in container for bind mounting
- Container must have `mount` command available
- Works with any Node.js version
- Compatible with all major package managers (npm, yarn, pnpm)
