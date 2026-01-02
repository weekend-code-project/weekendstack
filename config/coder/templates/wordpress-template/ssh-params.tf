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

locals {
  ssh_password = data.coder_parameter.ssh_password.value != "" ? data.coder_parameter.ssh_password.value : random_password.workspace_secret.result
  ssh_port = 50000 + (parseint(substr(data.coder_workspace.me.id, 0, 8), 16) % 15000)
  
  ssh_docker_ports = data.coder_parameter.ssh_enable.value ? {
    internal = 22
    external = local.ssh_port
  } : null
  
  ssh_copy_script = data.coder_parameter.ssh_enable.value ? join("\n", [
    "#!/bin/bash",
    "echo '[SSH] 📋 Copying SSH keys from host...'",
    "mkdir -p ~/.ssh",
    "chmod 700 ~/.ssh",
    "if [ -d \"/mnt/host-ssh\" ] && [ -f \"/mnt/host-ssh/id_rsa.pub\" ]; then",
    "  cp /mnt/host-ssh/id_rsa.pub ~/.ssh/authorized_keys 2>/dev/null || true",
    "  chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true",
    "fi"
  ]) : "# SSH disabled"
  
  ssh_setup_script = data.coder_parameter.ssh_enable.value ? join("\n", [
    "#!/bin/bash",
    "echo '[SSH] 🔐 Setting up SSH server...'",
    "sudo apt-get update -qq > /dev/null 2>&1",
    "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server > /dev/null 2>&1",
    "echo \"coder:${local.ssh_password}\" | sudo chpasswd",
    "sudo service ssh start > /dev/null 2>&1",
    "echo '[SSH] ✅ SSH server ready on port ${local.ssh_port}'"
  ]) : "# SSH disabled"
}
