# Docker Integration Module

Complete Docker-in-Docker integration for Coder workspaces including installation, configuration, and container resources.

## Usage

```hcl
module "docker" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/docker-integration?ref=PLACEHOLDER"
  
  workspace_id          = data.coder_workspace.me.id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner_name  = data.coder_workspace_owner.me.name
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  agent_token           = coder_agent.main.token
  agent_init_script     = coder_agent.main.init_script
  
  # Optional
  coder_access_url  = "http://coder:7080"
  workspace_dir     = ""  # Set via TF_VAR_workspace_dir for bind mount
  ssh_key_dir       = ""  # Set via TF_VAR_ssh_key_dir for SSH keys
  traefik_labels    = {}  # From traefik module
  ssh_enabled       = false
  ssh_port          = "2222"
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| workspace_id | Workspace UUID | string | yes | - |
| workspace_name | Workspace name | string | yes | - |
| workspace_owner_name | Owner username | string | yes | - |
| workspace_owner_id | Owner UUID | string | yes | - |
| workspace_start_count | Start count | number | yes | - |
| agent_token | Coder agent token | string | yes | - |
| agent_init_script | Agent init script | string | yes | - |
| coder_access_url | Coder URL | string | no | http://coder:7080 |
| workspace_dir | Host workspace path | string | no | "" |
| ssh_key_dir | Host SSH keys path | string | no | "" |
| traefik_auth_dir | Traefik auth path | string | no | /mnt/workspace/wcp-coder/config/traefik/auth |
| traefik_labels | Traefik labels map | map(string) | no | {} |
| ssh_enabled | Enable SSH port | bool | no | false |
| ssh_port | SSH port number | string | no | 2222 |
| container_image | Docker image | string | no | codercom/enterprise-base:ubuntu |
| docker_network | Network name | string | no | coder-network |

## Outputs

| Name | Description |
|------|-------------|
| docker_install_script | Docker installation script |
| docker_config_script | Docker daemon configuration script |
| home_volume_name | Home volume name |
| container_id | Container ID (if started) |

## Features

1. **Docker Installation**: Installs Docker Engine using official script
2. **Daemon Configuration**: Configures registry mirrors and insecure registries
3. **Persistent Home**: Docker volume for /home/coder
4. **Privileged Container**: Required for Docker-in-Docker
5. **Optional Bind Mounts**: Workspace files, SSH keys
6. **Traefik Integration**: Dynamic routing labels
7. **SSH Support**: Optional SSH port publishing
8. **Coder Metadata**: Proper labeling for resource tracking

## Architecture

- **True Docker-in-Docker**: Each workspace gets isolated daemon
- **Privileged Required**: Container must run with privileged = true
- **Persistent Storage**: Home directory persists via Docker volume
- **Network Isolation**: Uses coder-network for container communication
- **Host Gateway**: Access to host services via host.docker.internal

## Example in Startup Script

```hcl
resource "coder_agent" "main" {
  startup_script = join("\n", [
    module.docker.docker_install_script,
    module.docker.docker_config_script,
    # ... other scripts ...
  ])
}
```
