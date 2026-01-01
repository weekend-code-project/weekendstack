# =============================================================================
# SSH Server Configuration
# =============================================================================

data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for remote access."
  type         = "bool"
  default      = "false"
  mutable      = false
  order        = 100
}

data "coder_parameter" "ssh_password" {
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Optional custom password (leave empty for auto-generated)"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 101
}

module "ssh" {
  count  = data.coder_parameter.ssh_enable.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  workspace_id       = data.coder_workspace.me.id
  workspace_password = data.coder_parameter.ssh_password.value != "" ? data.coder_parameter.ssh_password.value : random_password.workspace_secret.result
  host_ip           = var.host_ip
}
