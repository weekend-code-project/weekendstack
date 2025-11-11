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
  # Use variables passed from template instead of coder_parameter data sources
  ssh_port_manual     = try(tonumber(trimspace(var.ssh_port_default)), 0)
  ssh_port_auto_value = random_integer.ssh_auto_port.result
  resolved_ssh_port   = tostring(
    var.ssh_port_mode_default == "auto" ? local.ssh_port_auto_value : local.ssh_port_manual
  )
}

# SSH Key Setup Script
output "ssh_copy_script" {
  description = "Script to setup SSH keys from host mount"
  value       = <<-EOT
    echo "[SSH] Setting up SSH keys from /mnt/host-ssh..."
    
    # Create .ssh directory with proper permissions
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Copy SSH keys from mounted directory (if any exist)
    if [ -n "$(ls -A /mnt/host-ssh 2>/dev/null)" ]; then
      cp -r /mnt/host-ssh/* ~/.ssh/ 2>/dev/null || true
      chmod 600 ~/.ssh/id_* 2>/dev/null || true
      chmod 644 ~/.ssh/id_*.pub 2>/dev/null || true
      chmod 600 ~/.ssh/config 2>/dev/null || true
      echo "[SSH] ✅ SSH keys copied from host"
    else
      echo "[SSH] ℹ️  No SSH keys found - generate with: ssh-keygen -t ed25519"
    fi
    
    # Create known_hosts and add GitHub
    touch ~/.ssh/known_hosts
    chmod 644 ~/.ssh/known_hosts
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
  EOT
}

# SSH Server Setup Script
output "ssh_setup_script" {
  description = "Script to configure and start SSH server"
  value       = <<-EOT
  if [ "${var.ssh_enable_default}" = "true" ]; then
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

      # Start SSH daemon in background (not -D daemon mode, just regular background)
      echo "[SSH] Starting SSH daemon on port 2222..."
      sudo /usr/sbin/sshd -f /etc/ssh/sshd_config
      
      # Verify it started
      sleep 1
      if pgrep sshd >/dev/null; then
        echo "[SSH] ✓ SSH daemon started successfully"
      else
        echo "[SSH] ✗ SSH daemon failed to start - check /tmp/sshd.log"
      fi

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
  echo ""
  echo "Connection command:"
  echo "  ssh -p ${local.resolved_ssh_port} coder@${var.host_ip}"
  echo ""
  echo "User: coder"
  echo "Password: ${var.workspace_password}"
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
  value       = var.ssh_enable_default
}

output "metadata_blocks" {
  description = "Metadata blocks contributed by this module"
  value = [
    {
      display_name = "SSH Port"
      script       = "echo ${local.resolved_ssh_port}"
      interval     = 60
      timeout      = 1
    },
    {
      display_name = "SSH Status"
      script       = "pgrep sshd >/dev/null && echo 'Running (port ${local.resolved_ssh_port})' || echo 'Not running'"
      interval     = 30
      timeout      = 2
    }
  ]
}

output "docker_ports" {
  description = "Docker port mappings for SSH (internal 2222 -> external resolved_ssh_port)"
  value = {
    internal = 2222
    external = tonumber(local.resolved_ssh_port)
  }
}
