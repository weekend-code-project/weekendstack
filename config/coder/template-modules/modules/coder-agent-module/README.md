# Coder Agent Module

Configures the Coder agent that runs inside workspace containers. Handles startup script composition, Git identity, and resource monitoring.

## Usage

```hcl
module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent?ref=PLACEHOLDER"
  
  arch       = data.coder_provisioner.me.arch
  os         = "linux"
  
  # Compose startup script from various modules
  startup_script = join("\n", [
    module.init_shell.script,
    module.docker.docker_install_script,
    module.docker.docker_config_script,
    # ... other scripts ...
    local.startup_epilogue,
  ])
  
  # Git identity
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  
  # Optional
  coder_access_url = "http://coder:7080"
  env_vars         = {
    SSH_PORT = "2222"
    PORTS    = "8080,3000"
  }
  metadata_blocks  = []
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| arch | Architecture | string | yes | - |
| os | Operating system | string | no | linux |
| startup_script | Complete startup script | string | yes | - |
| git_author_name | Git author name | string | yes | - |
| git_author_email | Git author email | string | yes | - |
| coder_access_url | Coder URL | string | no | http://coder:7080 |
| env_vars | Additional env variables | map(string) | no | {} |
| metadata_blocks | Resource monitoring | list(object) | no | [] |

## Outputs

| Name | Description |
|------|-------------|
| agent_id | Agent resource ID |
| agent_token | Agent auth token (sensitive) |
| agent_init_script | Agent initialization script |

## Features

1. **Startup Script Composition**: Combines multiple module scripts
2. **Git Identity**: Automatic Git configuration from workspace owner
3. **Resource Monitoring**: Configurable metadata blocks for CPU, RAM, disk
4. **Environment Variables**: Flexible env var injection
5. **Architecture Detection**: Supports amd64, arm64, etc.

## Metadata Block Example

```hcl
metadata_blocks = [
  {
    display_name = "CPU Usage"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"
    interval     = 10
    timeout      = 1
  },
  {
    display_name = "RAM Usage"
    script       = "free -h | awk '/^Mem/ {print $3}'"
    interval     = 10
    timeout      = 1
  }
]
```

## Startup Epilogue Example

```hcl
locals {
  startup_epilogue = <<-EOT
    echo "[STARTUP] ✅ All startup modules executed"
    date | tee /var/tmp/coder_startup_done >/dev/null
  EOT
}
```
