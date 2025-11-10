# Metadata Blocks Module

Provides configurable metadata blocks for workspace resource monitoring in the Coder UI.

## Usage

### Basic Usage (All Default Blocks)

```hcl
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/metadata?ref=v0.1.0"
}

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.0"
  
  # ... other config ...
  metadata_blocks = module.metadata.metadata_blocks
}
```

### Select Specific Blocks

```hcl
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/metadata?ref=v0.1.0"
  
  # Only show these metrics
  enabled_blocks = ["cpu", "ram", "disk"]
}
```

### Add Custom Blocks

```hcl
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/metadata?ref=v0.1.0"
  
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
| enabled_blocks | Block names to enable | list(string) | no | ["cpu", "ram", "disk", "arch", "ports", "ssh_port", "validation"] |
| custom_blocks | Custom metadata blocks | list(object) | no | [] |

## Outputs

| Name | Description |
|------|-------------|
| metadata_blocks | List of metadata block definitions |

## Available Blocks

| Block Name | Display Name | Description | Interval | Timeout |
|------------|--------------|-------------|----------|---------|
| `cpu` | CPU Usage | Current CPU usage | 10s | 1s |
| `ram` | RAM Usage | Current RAM usage | 10s | 1s |
| `disk` | Disk Usage | Home directory disk usage | 60s | 1s |
| `arch` | Architecture | System architecture (amd64, arm64) | 60s | 5s |
| `ports` | Ports | Exposed ports from $PORTS env var | 60s | 1s |
| `ssh_port` | SSH Port | SSH port from $SSH_PORT env var | 60s | 1s |
| `validation` | Validation | Workspace validation status | 30s | 1s |
| `load_avg` | Load Average | System load average | 30s | 1s |
| `uptime` | Uptime | System uptime | 60s | 1s |

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

- Scripts run inside the workspace container
- Scripts have access to environment variables (PORTS, SSH_PORT, etc.)
- Lower intervals = more frequent updates = higher resource usage
- Scripts should be fast and idempotent
- Use `coder stat` commands for system metrics (built-in to Coder)
