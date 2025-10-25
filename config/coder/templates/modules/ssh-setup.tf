# =============================================================================
# MODULE: SSH Setup
# =============================================================================
# Configures and starts an SSH server if enabled.

locals {
  ssh_setup = <<-EOT
    if [ "${data.coder_parameter.ssh_enable.value}" = "true" ]; then
        export SSH_PORT="${local.resolved_ssh_port}"
      if ! command -v sshd >/dev/null 2>&1; then
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
  echo "coder:${try(data.coder_parameter.workspace_secret[0].value, random_password.workspace_secret.result)}" | sudo chpasswd

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
