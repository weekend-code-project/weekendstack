# =============================================================================
# MODULE: SSH Integration
# =============================================================================
# Provides SSH server access to workspaces
# =============================================================================

# Parameters
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for direct SSH access."
  type         = "bool"
  form_type    = "switch"
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
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  order        = 52
  
  styling = jsonencode({
    disabled = try(data.coder_parameter.ssh_port_mode[0].value, "auto") == "auto"
  })
  
  validation {
    regex = "^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
    error = "SSH port must be a valid port number between 1 and 65535"
  }
}

data "coder_parameter" "ssh_password" {
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Password for SSH access. Leave empty to use auto-generated password."
  type         = "string"
  default      = ""
  mutable      = true
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  order        = 53
}

# Module
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/ssh-integration?ref=v0.1.0"
  
  workspace_id          = data.coder_workspace.me.id
  workspace_password    = try(data.coder_parameter.ssh_password[0].value, "") != "" ? try(data.coder_parameter.ssh_password[0].value, "") : random_password.workspace_secret.result
  ssh_enable_default    = data.coder_parameter.ssh_enable.value
  ssh_port_mode_default = try(data.coder_parameter.ssh_port_mode[0].value, "auto")
  ssh_port_default      = try(data.coder_parameter.ssh_port[0].value, "")
}
