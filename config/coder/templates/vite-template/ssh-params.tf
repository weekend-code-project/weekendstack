# =============================================================================
# SSH Parameters (Vite Template Override)
# =============================================================================
# OVERRIDE NOTE: Removes conditional styling to prevent UI flickering

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

# Parameter: SSH Password (NO conditional styling - prevents flickering)
data "coder_parameter" "ssh_password" {
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Optional custom password (leave empty for auto-generated)"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 51
  # NO styling block - always visible to prevent UI flickering
}

# Module: SSH (conditional - only loaded when enabled)
module "ssh" {
  count  = data.coder_parameter.ssh_enable.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  workspace_id       = data.coder_workspace.me.id
  workspace_name     = data.coder_workspace.me.name
  workspace_password = data.coder_parameter.ssh_password.value != "" ? data.coder_parameter.ssh_password.value : random_password.workspace_secret.result
  ssh_enable_default = data.coder_parameter.ssh_enable.value
  host_ip            = var.host_ip
}
