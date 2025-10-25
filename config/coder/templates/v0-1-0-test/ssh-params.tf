# =============================================================================
# SSH Parameters
# =============================================================================
# Required by git-modules/ssh-integration module
# Copy this file to use SSH integration in your template

# SSH Enable Toggle - Always visible
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for direct SSH access."
  type         = "bool"
  default      = false
  mutable      = true
  order        = 50
}

# SSH Port Mode - Only show when SSH is enabled
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

# SSH Port - Show when SSH enabled, disable when in auto mode
data "coder_parameter" "ssh_port" {
  name         = "ssh_port"
  display_name = "SSH Port"
  description  = "Container port to run sshd on (also published on the router as needed)."
  type         = "string"
  default      = "2221"
  mutable      = true
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  order        = 52
  
  # Disable the field when in auto mode using styling
  styling = jsonencode({
    disabled = try(data.coder_parameter.ssh_port_mode[0].value, "auto") == "auto"
  })
  
  # Validate it's a valid port number
  validation {
    regex = "^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
    error = "SSH port must be a valid port number between 1 and 65535"
  }
}

# SSH Password - Required when SSH is enabled
data "coder_parameter" "ssh_password" {
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Password for SSH access (leave empty to use workspace secret)"
  type         = "string"
  default      = ""
  mutable      = true
  count        = data.coder_parameter.ssh_enable.value ? 1 : 0
  order        = 53
}
