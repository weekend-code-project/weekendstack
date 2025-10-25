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
  order        = 51
}

data "coder_parameter" "ssh_port_mode" {
  name         = "ssh_port_mode"
  display_name = "SSH Port Mode"
  description  = "Choose 'manual' to specify a port, or 'auto' to pick a stable open port automatically."
  type         = "string"
  default      = "manual"
  mutable      = true
  option {
    name  = "manual"
    value = "manual"
  }
  option {
    name  = "auto"
    value = "auto"
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
  ssh_port_manual     = try(tonumber(trimspace(data.coder_parameter.ssh_port.value)), 0)
  ssh_port_auto_value = random_integer.ssh_auto_port.result
  resolved_ssh_port   = tostring(
    data.coder_parameter.ssh_port_mode.value == "auto" ? local.ssh_port_auto_value : local.ssh_port_manual
  )
}
