# =============================================================================
# SSH Parameters (Vite Template Override)
# =============================================================================
# OVERRIDE NOTE: Removes conditional patterns to prevent UI flickering

# Parameter: Enable SSH Server (mutable, no dependencies)
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

# Parameter: SSH Password (always visible - no conditional styling to prevent flicker)
data "coder_parameter" "ssh_password" {
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Optional custom password (leave empty for auto-generated)"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 51
}

# Module: SSH (ALWAYS loaded - no count conditional to prevent flickering)
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  workspace_id       = data.coder_workspace.me.id
  workspace_name     = data.coder_workspace.me.name
  workspace_password = data.coder_parameter.ssh_password.value != "" ? data.coder_parameter.ssh_password.value : random_password.workspace_secret.result
  ssh_enable_default = data.coder_parameter.ssh_enable.value
  host_ip            = var.host_ip
}
