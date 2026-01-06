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

# Deterministic per-workspace auto port in a high range to avoid conflicts
resource "random_integer" "ssh_auto_port" {
  min = 23000
  max = 29999
  keepers = {
    workspace_id = var.workspace_id
  }
}

locals {
  # Always use auto-generated port (deterministic per workspace UUID)
  resolved_ssh_port = tostring(random_integer.ssh_auto_port.result)
}

# SSH Key Setup Script
output "ssh_copy_script" {
  description = "Script to setup SSH keys from host mount"
  value       = <<-EOT
    # SSH keys are handled by git-identity module now
    # This is kept for backwards compatibility but does nothing
    true
  EOT
}

# SSH Server Setup Script
output "ssh_setup_script" {
  description = "Script to configure and start SSH server"
  value       = <<-EOT
  if [ "${var.ssh_enable_default}" = "true" ]; then
      export SSH_PORT="${local.resolved_ssh_port}"
      
      # Install SSH server if needed
      if ! command -v sshd >/dev/null 2>&1; then
        echo "[SSH] Installing OpenSSH server..."
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y openssh-server >/dev/null 2>&1
      fi

      SSH_PERSIST="$HOME/.persist/ssh"
      SSH_HOSTKEYS_DIR="$SSH_PERSIST/hostkeys"

      mkdir -p "$SSH_HOSTKEYS_DIR"
      chmod 700 "$SSH_PERSIST"

      # Generate host keys if missing (silent)
      [ -f "$SSH_HOSTKEYS_DIR/ssh_host_ed25519_key" ] || sudo ssh-keygen -t ed25519 -f "$SSH_HOSTKEYS_DIR/ssh_host_ed25519_key" -N "" >/dev/null 2>&1
      [ -f "$SSH_HOSTKEYS_DIR/ssh_host_rsa_key" ]     || sudo ssh-keygen -t rsa -b 4096 -f "$SSH_HOSTKEYS_DIR/ssh_host_rsa_key" -N "" >/dev/null 2>&1
      sudo chmod 600 "$SSH_HOSTKEYS_DIR"/ssh_host_* 2>/dev/null

      # Configure SSHD
      sudo mkdir -p /etc/ssh
      sudo tee /etc/ssh/sshd_config >/dev/null <<CFG
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
      echo "coder:${var.workspace_password}" | sudo chpasswd 2>/dev/null

      # Setup workspace auto-cd for SSH sessions
      if ! grep -q 'Auto-cd to workspace on SSH login' ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc <<'BRC'
# Auto-cd to workspace on SSH login
if [ -n "$SSH_CONNECTION" ] && [ -d "$HOME/workspace" ]; then
  cd "$HOME/workspace" 2>/dev/null || true
fi
BRC
      fi

      sudo tee /etc/profile.d/10-cd-workspace.sh >/dev/null <<'PROF'
# Auto-cd to workspace on SSH login (login shell)
if [ -n "$SSH_CONNECTION" ] && [ -d "$HOME/workspace" ]; then
  cd "$HOME/workspace" 2>/dev/null || true
fi
PROF

      # Start SSH daemon
      sudo /usr/sbin/sshd -f /etc/ssh/sshd_config 2>/dev/null
      
      # Verify it started and display connection info
      sleep 1
      if pgrep sshd >/dev/null; then
        echo "[SSH] ✓ Enabled: ssh -p ${local.resolved_ssh_port} coder@${var.host_ip}"
        # Write external port to file for metadata display
        echo "${local.resolved_ssh_port}" > "$HOME/.ssh_external_port"
        # Only show password if it's auto-generated (starts with workspace UUID)
        if [[ "${var.workspace_password}" == "${var.workspace_id}"* ]]; then
          echo "[SSH] Password: ${var.workspace_password}"
        fi
      else
        echo "[SSH] ✗ Failed to start SSH daemon"
      fi
      
      echo ""  # Line break after module
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
  value       = var.ssh_enable_default
}

# SSH port metadata is now handled via the metadata picker in metadata-params.tf
# This output is kept for compatibility but returns empty list
output "metadata_blocks" {
  description = "Metadata blocks contributed by this module (now handled via metadata picker)"
  value = []
}

output "docker_ports" {
  description = "Docker port mappings for SSH (internal 2222 -> external resolved_ssh_port)"
  value = var.ssh_enable_default == true ? {
    internal = 2222
    external = tonumber(local.resolved_ssh_port)
  } : null
}
