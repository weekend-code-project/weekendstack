# Metadata Blocks Module

Provides configurable metadata blocks for workspace resource monitoring in the Coder UI.

## Overview

This module provides **agent metadata** blocks for live workspace monitoring. It integrates with Coder's metadata system to display real-time operational metrics in the UI.

Modules can dynamically contribute their own metadata blocks (e.g., Docker module adds "Docker Status" when enabled).

## Usage

### Basic Usage (With UI Parameter)

Typically used via `metadata-params.tf` overlay which provides a UI dropdown:

```hcl
# In template - metadata-params.tf is auto-overlaid
# User selects metadata blocks from UI dropdown
# Module automatically includes custom blocks from loaded modules

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent?ref=PLACEHOLDER"
  
  # ... other config ...
  metadata_blocks = module.metadata.metadata_blocks
}
```

### Direct Module Usage (No UI)

```hcl
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata?ref=PLACEHOLDER"
  
  # Only show these metrics
  enabled_blocks = ["cpu", "ram", "disk"]
}
```

### Dynamic Module Contributions

Modules can contribute metadata blocks that appear automatically when the module is loaded:

```hcl
# In template's agent-params.tf
locals {
  docker_metadata = try(module.docker[0].metadata_blocks, [])
  ssh_metadata = try(module.ssh[0].metadata_blocks, [])
  
  # Collect all module contributions
  all_custom_metadata = concat(
    local.docker_metadata,
    local.ssh_metadata
  )
}

# metadata-params.tf references this local
module "metadata" {
  source = "..."
  enabled_blocks = [...] # From UI parameter
  custom_blocks = local.all_custom_metadata  # From loaded modules
}
```

### Custom Blocks Example

```hcl
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata?ref=PLACEHOLDER"
  
  enabled_blocks = ["cpu", "ram"]
  
  custom_blocks = [
    {
      display_name = "Docker Containers"
      script       = "docker ps --format 'table {{.Names}}' | tail -n +2 | wc -l"
      interval     = 30
      timeout      = 5
    },
    {
      display_name = "Git Branch"
      script       = "cd ~/workspace && git branch --show-current 2>/dev/null || echo 'N/A'"
      interval     = 60
      timeout      = 2
    }
  ]
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| enabled_blocks | Block names to enable | list(string) | no | ["cpu", "ram", "disk", "arch", "validation"] |
| custom_blocks | Custom metadata blocks contributed by other modules | list(object) | no | [] |

## Outputs

| Name | Description |
|------|-------------|
| metadata_blocks | List of metadata block definitions |

## Available Blocks

**Base blocks** (selectable via UI parameter):

| Block Name | Display Name | Description | Interval | Timeout |
|------------|--------------|-------------|----------|---------|
| `cpu` | CPU Usage | Current CPU usage via `coder stat cpu` | 10s | 1s |
| `ram` | RAM Usage | Current RAM usage via `coder stat mem` | 10s | 1s |
| `disk` | Disk Usage | Home directory disk usage via `coder stat disk` | 60s | 1s |
| `arch` | Architecture | System architecture (amd64, arm64) | 60s | 5s |
| `validation` | Validation | Workspace validation status | 30s | 1s |
| `load_avg` | Load Average | System load average | 30s | 1s |
| `uptime` | Uptime | System uptime | 60s | 1s |

**Module-contributed blocks** (automatically added when modules are loaded):

| Module | Block Name | Display Name | Description |
|--------|------------|--------------|-------------|
| docker | docker_status | Docker Status | Docker version and container count |
| ssh (future) | ssh_port | SSH Port | Active SSH port |
| git (future) | git_branch | Git Branch | Current repository branch |

## Custom Block Structure

```hcl
{
  display_name = "Display Name"  # Shown in UI
  script       = "command"       # Bash script to run
  interval     = 30              # Seconds between runs
  timeout      = 5               # Seconds before timeout
}
```

## Examples

### Minimal Monitoring

```hcl
enabled_blocks = ["cpu", "ram"]
```

### Development Workspace

```hcl
enabled_blocks = ["cpu", "ram", "disk", "ports", "validation"]
```

### SSH-Enabled Workspace

```hcl
enabled_blocks = ["cpu", "ram", "ssh_port", "arch"]
```

### No Monitoring

```hcl
enabled_blocks = []
```

## Notes

- **Agent Metadata vs Resource Metadata**: This module provides agent metadata (live metrics). For static resource metadata, use `coder_metadata` resources (see [Coder docs](https://coder.com/docs/templates/resource-metadata))
- Scripts run inside the workspace container with workspace user permissions
- Scripts have access to workspace environment variables
- Lower intervals = more frequent updates = higher database write load
- Scripts should be fast and idempotent
- Use `coderstat` commands for system metrics (built-in to Coder, more accurate)
- **Database Load**: Approximate writes/sec = `(metadata_count * num_agents * 2) / avg_interval`
  - Example: 10 agents × 6 metadata × 2 / 4s interval = 30 writes/sec
- **Module Contributions**: Modules automatically add metadata when enabled (e.g., Docker adds status block when docker is enabled)

## TODO: Low Priority Enhancements

- [ ] Add `key` field to metadata blocks for better API compatibility
- [ ] Add `coder_metadata` resources for Docker volume and container info
- [ ] Consider adding icons to metadata blocks using `/icon/` paths
- [ ] Review interval timings for database load optimization
