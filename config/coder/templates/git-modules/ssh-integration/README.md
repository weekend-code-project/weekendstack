# SSH Integration Module

Complete SSH integration for Coder workspaces including key management and SSH server setup.

## Usage

```hcl
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/ssh-integration?ref=v0.1.0"
  
  workspace_id       = data.coder_workspace.me.id
  workspace_password = random_password.workspace_secret.result
}

# Include in agent startup script
resource "coder_agent" "main" {
  startup_script = join("\n", [
    module.ssh.ssh_copy_script,
    # ... other scripts ...
    module.ssh.ssh_setup_script,
  ])
  
  env = {
    SSH_PORT = module.ssh.ssh_port
  }
}

# Use in docker container
resource "docker_container" "workspace" {
  ports {
    internal = 2222
    external = module.ssh.ssh_enabled ? tonumber(module.ssh.ssh_port) : 0
  }
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| workspace_id | Workspace UUID | string | yes | - |
| workspace_password | SSH password | string | yes | - |
| ssh_enable_default | SSH enable default | bool | no | false |
| ssh_port_default | SSH port default | string | no | "" |
| ssh_port_mode_default | Port mode default | string | no | "manual" |

## Outputs

| Name | Description |
|------|-------------|
| ssh_copy_script | Script to copy SSH keys |
| ssh_setup_script | Script to setup SSH server |
| ssh_port | Resolved SSH port |
| ssh_enabled | Whether SSH is enabled |

## Features

1. **SSH Key Copying**: Copies keys from `/mnt/host-ssh` if available
2. **SSH Server**: Installs and configures OpenSSH server
3. **Auto/Manual Ports**: Flexible port selection
4. **Persistent Host Keys**: Host keys stored in `~/.persist/ssh`
5. **Password Auth**: Uses workspace password for SSH login
6. **Auto-CD**: SSH sessions start in workspace directory

## Coder Parameters

This module creates three user-configurable parameters:
- `ssh_enable`: Enable/disable SSH server
- `ssh_port`: Manual port specification
- `ssh_port_mode`: Choose auto or manual port selection
