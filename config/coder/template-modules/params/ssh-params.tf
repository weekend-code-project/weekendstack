# =============================================================================
# SSH Module
# =============================================================================
# DESCRIPTION:
#   Provides SSH server functionality for workspace remote access.
#   Includes host key management, password authentication, and auto port selection.
#
# PARAMETERS:
#   - ssh_enable: Boolean toggle to enable SSH server
#   - ssh_port_mode: Auto or manual port selection (conditional on ssh_enable)
#   - ssh_port: Manual port number (conditional on ssh_enable AND manual mode)
#   - ssh_password: Optional password override (conditional on ssh_enable)
#
# DEPENDENCIES:
#   - template-modules/modules/ssh-module: SSH server setup scripts
#   - random_password.workspace_secret: Generated password (if not manually set)
#
# OUTPUTS (via module.ssh):
#   - ssh_copy_script: Script to copy SSH keys from host mount
#   - ssh_setup_script: Script to configure and start SSH server
#   - ssh_port: Resolved SSH port (auto or manual)
#   - ssh_enabled: Whether SSH is enabled
#   - metadata_blocks: SSH Port metadata (when enabled)
#
# USAGE IN AGENT:
#   startup_script = join("\n", [
#     try(module.ssh[0].ssh_copy_script, ""),
#     try(module.ssh[0].ssh_setup_script, "")
#   ])
#
# NOTES:
#   - Uses conditional count pattern (HIGH flickering risk)
#   - Port mode uses disabled styling (MEDIUM flickering risk)
#   - Auto port: Deterministic random (23000-29999) based on workspace ID
#   - Manual port: User-defined (validated 1-65535)
# =============================================================================

# Parameter: Enable SSH Server
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for remote access."
  type         = "bool"
  form_type    = "switch"
  default      = "false"
  mutable      = true
  order        = 50
}

# Parameter: SSH Port Mode (conditional on ssh_enable)
data "coder_parameter" "ssh_port_mode" {
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  name         = "ssh_port_mode"
  display_name = "SSH Port Mode"
  description  = "Choose 'auto' for automatic port assignment or 'manual' to specify a port."
  type         = "string"
  default      = "auto"
  mutable      = true
  order        = 51

  option {
    name  = "Auto (Random)"
    value = "auto"
  }

  option {
    name  = "Manual"
    value = "manual"
  }
}

# Parameter: SSH Port (conditional on ssh_enable, disabled when auto mode)
data "coder_parameter" "ssh_port" {
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  name         = "ssh_port"
  display_name = "SSH Port"
  description  = "Container port for SSH server (ignored in auto mode)."
  type         = "string"
  default      = "2221"
  mutable      = true
  order        = 52
  
  # Disable field when in auto mode
  styling = jsonencode({ 
    disabled = try(data.coder_parameter.ssh_port_mode[0].value, "auto") == "auto" 
  })

  validation {
    regex = "^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
    error = "SSH port must be between 1 and 65535"
  }
}

# Parameter: SSH Password (conditional on ssh_enable)
data "coder_parameter" "ssh_password" {
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Optional custom password. Leave empty to use auto-generated workspace password."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 53
}

# Module: SSH (conditional - only loaded when enabled)
module "ssh" {
  count  = data.coder_parameter.ssh_enable.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  workspace_id          = data.coder_workspace.me.id
  workspace_password    = try(data.coder_parameter.ssh_password[0].value, "") != "" ? try(data.coder_parameter.ssh_password[0].value, "") : random_password.workspace_secret.result
  ssh_enable_default    = data.coder_parameter.ssh_enable.value
  ssh_port_mode_default = try(data.coder_parameter.ssh_port_mode[0].value, "auto")
  ssh_port_default      = try(data.coder_parameter.ssh_port[0].value, "")
  host_ip               = var.host_ip
}
