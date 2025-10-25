# =============================================================================
# MODULE PARAMS: SSH
# =============================================================================

data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for direct SSH access."
  type         = "bool"
  default      = false
  mutable      = true
  order        = 50
}

data "coder_parameter" "ssh_port" {
  name         = "ssh_port"
  display_name = "SSH Port"
  description  = "Container port to run sshd on (also published on the router as needed)."
  type         = "string"
  default      = ""
  mutable      = true
  # Only show the SSH port field when SSH is enabled AND the port mode is set to manual
  count = data.coder_parameter.ssh_enable.value ? (data.coder_parameter.ssh_port_mode.value == "manual" ? 1 : 0) : 0
  order        = 51
}

data "coder_parameter" "ssh_port_mode" {
  name         = "ssh_port_mode"
  display_name = "SSH Port Mode"
  description  = "Choose 'manual' to specify a port, or 'auto' to pick a stable open port automatically."
  type         = "string"
  # Make 'auto' the default and list it first in the UI
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
  order = 52
}

# Deterministic per-workspace auto port in a high range to avoid conflicts
resource "random_integer" "ssh_auto_port" {
  min = 23000
  max = 29999
  keepers = {
    workspace_id = data.coder_workspace.me.id
  }
}

locals {
  # When ssh_port is hidden (count = 0) the data source becomes an empty list; use try(..., "")
  ssh_port_manual     = try(tonumber(trimspace(try(data.coder_parameter.ssh_port[0].value, ""))), 0)
  ssh_port_auto_value = random_integer.ssh_auto_port.result
  resolved_ssh_port   = tostring(
    data.coder_parameter.ssh_port_mode.value == "auto" ? local.ssh_port_auto_value : local.ssh_port_manual
  )
}
