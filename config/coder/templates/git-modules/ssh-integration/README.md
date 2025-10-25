# SSH Integration Module

Complete SSH integration for Coder workspaces including key management and SSH server setup.

## Requirements

⚠️ **Important**: This module requires you to define the SSH parameters in your template's root module. The module receives these parameter values as inputs.

### Required Template Parameters

Add these to your template's `main.tf`:

```hcl
# SSH Parameters (must be in template root, not in module)
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for direct SSH access."
  type         = "bool"
  default      = false
  mutable      = true
  order        = 50
}

data "coder_parameter" "ssh_port_mode" {
  name         = "ssh_port_mode"
  display_name = "SSH Port Mode"
  description  = "Choose 'manual' to specify a port, or 'auto' to pick a stable open port automatically."
  type         = "string"
  default      = "auto"
  mutable      = true
  option {
    name  = "auto"
    value = "auto"
  }
  option {
    name  = "manual"
    value = "manual"
  }
  count = data.coder_parameter.ssh_enable.value ? 1 : 0
  order = 51
}

data "coder_parameter" "ssh_port" {
  name         = "ssh_port"
  display_name = "SSH Port"
  description  = "Container port to run sshd on (also published on the router as needed)."
  type         = "string"
  default      = "2221"
  mutable      = true
  count = data.coder_parameter.ssh_enable.value ? 1 : 0
  order = 52
  
  styling = jsonencode({
    disabled = try(data.coder_parameter.ssh_port_mode[0].value, "auto") == "auto"
  })
  
  validation {
    regex = "^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
    error = "SSH port must be a valid port number between 1 and 65535"
  }
}
```

## Usage

```hcl
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/ssh-integration?ref=v0.1.0"
  
  workspace_id          = data.coder_workspace.me.id
  workspace_password    = random_password.workspace_secret.result
  ssh_enable_default    = data.coder_parameter.ssh_enable.value
  ssh_port_mode_default = try(data.coder_parameter.ssh_port_mode[0].value, "auto")
  ssh_port_default      = try(data.coder_parameter.ssh_port[0].value, "")
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
| ssh_port_mode_default | Port mode default | string | no | "auto" |

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

## How It Works

The module receives parameter values from your template and:

1. **SSH Enable**: Controls whether SSH components are created
2. **Port Mode** ("auto" or "manual"):
   - **auto**: Generates a deterministic random port (23000-29999) based on workspace ID
   - **manual**: Uses the user-specified port from `ssh_port` parameter
3. **SSH Scripts**: Outputs scripts for key copying and SSH server setup
