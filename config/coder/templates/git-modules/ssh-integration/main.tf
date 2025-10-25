# =============================================================================
# MODULE: SSH Integration
# =============================================================================
# DESCRIPTION:
#   Complete SSH integration including:
#   - SSH key copying from host
#   - SSH server setup and configuration
#   - Password authentication
#
# USAGE:
#   This module outputs setup scripts that should be included in the
#   coder_agent startup_script.
#
# OUTPUTS:
#   - ssh_copy_script: Script to copy SSH keys from host
#   - ssh_setup_script: Script to configure and start SSH server
#   - ssh_parameters: Coder parameter definitions for SSH configuration
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# SSH Parameters
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start an SSH server inside the workspace for direct SSH access."
  type         = "bool"
  default      = var.ssh_enable_default
  mutable      = true
  order        = 50
}

data "coder_parameter" "ssh_port" {
  name         = "ssh_port"
  display_name = "SSH Port"
  description  = "Container port to run sshd on (also published on the router as needed)."
  type         = "string"
  default      = var.ssh_port_default
  mutable      = true
  order        = 51
}

data "coder_parameter" "ssh_port_mode" {
  name         = "ssh_port_mode"
  display_name = "SSH Port Mode"
  description  = "Choose 'manual' to specify a port, or 'auto' to pick a stable open port automatically."
  type         = "string"
  default      = var.ssh_port_mode_default
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
    workspace_id = var.workspace_id
  }
}

locals {
  ssh_port_manual     = try(tonumber(trimspace(coder_parameter.ssh_port.value)), 0)
  ssh_port_auto_value = random_integer.ssh_auto_port.result
  resolved_ssh_port   = tostring(
    coder_parameter.ssh_port_mode.value == "auto" ? local.ssh_port_auto_value : local.ssh_port_manual
  )
}

# SSH Key Copy Script
output "ssh_copy_script" {
  description = "Script to copy SSH keys from host mount"
  value       = <<-EOT
    if [ -d "/mnt/host-ssh" ]; then
      echo "[SSH COPY] Installing SSH keys from /mnt/host-ssh..."
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      if [ -f "/mnt/host-ssh/id_ed25519" ]; then
        cp /mnt/host-ssh/id_ed25519 ~/.ssh/id_ed25519
        chmod 600 ~/.ssh/id_ed25519
      fi
      if [ -f "/mnt/host-ssh/id_ed25519.pub" ]; then
        cp /mnt/host-ssh/id_ed25519.pub ~/.ssh/id_ed25519.pub
        chmod 644 ~/.ssh/id_ed25519.pub
      fi
      touch ~/.ssh/known_hosts
      chmod 644 ~/.ssh/known_hosts
      ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
      echo "[SSH COPY] ✅ Keys installed."
    fi
  EOT
}

# SSH Server Setup Script
output "ssh_setup_script" {
  description = "Script to configure and start SSH server"
  value       = <<-EOT
    if [ "${coder_parameter.ssh_enable.value}" = "true" ]; then
      export SSH_PORT="${local.resolved_ssh_port}"
      
      if ! command -v sshd >/dev/null 2>&1; then
        echo "[SSH] Installing OpenSSH server..."
        sudo apt-get update
        sudo apt-get install -y openssh-server
      fi

      SSH_PERSIST="$HOME/.persist/ssh"
      SSH_HOSTKEYS_DIR="$SSH_PERSIST/hostkeys"

      mkdir -p "$SSH_HOSTKEYS_DIR"
      chmod 700 "$SSH_PERSIST"

      # Generate host keys if missing
      [ -f "$SSH_HOSTKEYS_DIR/ssh_host_ed25519_key" ] || sudo ssh-keygen -t ed25519 -f "$SSH_HOSTKEYS_DIR/ssh_host_ed25519_key" -N ""
      [ -f "$SSH_HOSTKEYS_DIR/ssh_host_rsa_key" ]     || sudo ssh-keygen -t rsa -b 4096 -f "$SSH_HOSTKEYS_DIR/ssh_host_rsa_key" -N ""
      sudo chmod 600 "$SSH_HOSTKEYS_DIR"/ssh_host_*

      sudo mkdir -p /etc/ssh
      sudo tee /etc/ssh/sshd_config >/dev/null <<CFG
        # Always listen on internal 2222; external port is handled by Docker publishing
        Port 2222
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
UsePAM yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp /usr/lib/openssh/sftp-server
HostKey $SSH_HOSTKEYS_DIR/ssh_host_ed25519_key
HostKey $SSH_HOSTKEYS_DIR/ssh_host_rsa_key
AllowUsers coder
CFG

      sudo mkdir -p /var/run/sshd
      echo "coder:${var.workspace_password}" | sudo chpasswd

      # Preload GitHub host key
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      touch ~/.ssh/known_hosts
      ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true

      sudo /usr/sbin/sshd -D > /tmp/sshd.log 2>&1 &

      # Ensure SSH sessions start in the workspace directory by default
      if ! grep -q 'Auto-cd to workspace on SSH login' ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc <<'BRC'
# Auto-cd to workspace on SSH login
if [ -n "$SSH_CONNECTION" ] && [ -d "$HOME/workspace" ] && [ "$PWD" = "$HOME" ]; then
  cd "$HOME/workspace"
fi
BRC
      fi

      # Also ensure login shells (via /etc/profile) cd into workspace if appropriate
      sudo tee /etc/profile.d/10-cd-workspace.sh >/dev/null <<'PROF'
# Auto-cd to workspace on SSH login (login shell)
if [ -n "$SSH_CONNECTION" ] && [ -d "$HOME/workspace" ]; then
  if [ "$PWD" = "$HOME" ]; then
    cd "$HOME/workspace"
  fi
fi
PROF

      echo ""
      echo "====================================="
      echo "SSH is enabled for this workspace."
      echo "User: coder"
      echo "Port: ${local.resolved_ssh_port}"
      echo "Password: [workspace secret]"
      echo "====================================="
      echo ""
    fi
  EOT
}

# Output resolved SSH port
output "ssh_port" {
  description = "The resolved SSH port (either manual or auto)"
  value       = local.resolved_ssh_port
}

output "ssh_enabled" {
  description = "Whether SSH is enabled"
  value       = coder_parameter.ssh_enable.value
}
