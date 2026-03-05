# =============================================================================
# MODULE: SSH Server
# =============================================================================
# Provides SSH access to the workspace with:
#   - OpenSSH server on a deterministic port (23000-29999)
#   - Persistent host keys (survive workspace restarts)
#   - Known hosts for common Git providers (GitHub, GitLab, Gitea)
#   - Connection info displayed in build log
#
# Git SSH authentication is handled natively by Coder via $GIT_SSH_COMMAND.
# No manual key generation or mounting is needed.
#
# The SSH port is deterministic per workspace (based on workspace_id),
# so it stays the same across restarts and rebuilds.
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "workspace_id" {
  description = "Workspace ID (used for deterministic port generation)"
  type        = string
}

variable "workspace_name" {
  description = "Workspace name (used in SSH key comment and display)"
  type        = string
  default     = "workspace"
}

variable "password" {
  description = "SSH login password for the coder user"
  type        = string
  sensitive   = true
}

variable "host_ip" {
  description = "Host IP address shown in SSH connection instructions"
  type        = string
  default     = "127.0.0.1"
}

# =============================================================================
# Deterministic SSH Port
# =============================================================================
# Generates a stable port in 23000-29999 based on workspace_id.
# Same workspace always gets the same port, even after rebuild.

resource "random_integer" "ssh_port" {
  min = 23000
  max = 29999
  keepers = {
    workspace_id = var.workspace_id
  }
}

locals {
  ssh_port      = random_integer.ssh_port.result
  internal_port = 2222
}

# =============================================================================
# SSH Server Setup + Key Generation (coder_script)
# =============================================================================

resource "coder_script" "ssh_setup" {
  agent_id           = var.agent_id
  display_name       = "SSH Server"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false  # Don't block IDE access while SSH installs

  script = <<-EOT
    #!/bin/bash
    set -e

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SSH] Setting up SSH server and generating keys..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ── 1. Install OpenSSH server if needed ──
    if ! command -v sshd >/dev/null 2>&1; then
      echo "[SSH] Installing OpenSSH server..."
      # Use flock to serialize apt operations across concurrent startup scripts
      (
        flock -w 300 9 || { echo "[SSH] WARNING: Could not acquire apt lock"; exit 1; }
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y -qq openssh-server >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[SSH] OpenSSH server installed"
    else
      echo "[SSH] OpenSSH server already installed"
    fi

    # ── 2. Persistent host keys (survive restarts via home volume) ──
    HOSTKEYS_DIR="$HOME/.persist/ssh/hostkeys"
    # Use sudo as fallback — .persist may be root-owned when mounted as a Docker volume
    mkdir -p "$HOSTKEYS_DIR" 2>/dev/null || sudo mkdir -p "$HOSTKEYS_DIR"
    sudo chown -R $(id -u):$(id -g) "$HOME/.persist/ssh" 2>/dev/null || true
    chmod 700 "$HOME/.persist/ssh"

    if [ ! -f "$HOSTKEYS_DIR/ssh_host_ed25519_key" ]; then
      echo "[SSH] Generating persistent host keys..."
      sudo ssh-keygen -t ed25519 -f "$HOSTKEYS_DIR/ssh_host_ed25519_key" -N "" >/dev/null 2>&1
      sudo ssh-keygen -t rsa -b 4096 -f "$HOSTKEYS_DIR/ssh_host_rsa_key" -N "" >/dev/null 2>&1
      echo "[SSH] Host keys generated"
    else
      echo "[SSH] Using existing host keys"
    fi
    sudo chmod 600 "$HOSTKEYS_DIR"/ssh_host_* 2>/dev/null

    # ── 3. Configure sshd ──
    sudo mkdir -p /etc/ssh /var/run/sshd
    sudo tee /etc/ssh/sshd_config >/dev/null <<SSHD_CFG
Port ${local.internal_port}
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
UsePAM yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp /usr/lib/openssh/sftp-server
HostKey $HOSTKEYS_DIR/ssh_host_ed25519_key
HostKey $HOSTKEYS_DIR/ssh_host_rsa_key
AllowUsers coder
SSHD_CFG

    # Set SSH password
    echo "coder:${var.password}" | sudo chpasswd 2>/dev/null

    # ── 4. Ensure .ssh directory exists ──
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # ── 5. Setup known_hosts for common Git providers ──
    touch "$HOME/.ssh/known_hosts"
    chmod 644 "$HOME/.ssh/known_hosts"

    echo "[SSH] Adding known hosts for Git providers..."
    for host in github.com gitlab.com bitbucket.org; do
      if ! grep -q "$host" "$HOME/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan -H "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
      fi
    done

    # Gitea / self-hosted Git (typically on port 2222)
    for gitea_host in gitea; do
      if ! grep -q "$gitea_host" "$HOME/.ssh/known_hosts" 2>/dev/null; then
        timeout 3 ssh-keyscan -H -p 2222 "$gitea_host" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
      fi
    done
    echo "[SSH] Known hosts configured"

    # ── 6. Auto-cd to workspace on SSH login ──
    if ! grep -q 'Auto-cd to workspace on SSH login' "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" <<'BASHRC'

# Auto-cd to workspace on SSH login
if [ -n "$SSH_CONNECTION" ] && [ -d "$HOME/workspace" ]; then
  cd "$HOME/workspace" 2>/dev/null || true
fi
BASHRC
    fi

    # ── 7. Start SSH daemon ──
    # Kill any existing sshd from previous start
    sudo pkill sshd 2>/dev/null || true
    sleep 1

    sudo /usr/sbin/sshd -f /etc/ssh/sshd_config 2>/dev/null
    sleep 1

    if pgrep sshd >/dev/null; then
      echo "[SSH] SSH server started on internal port ${local.internal_port}"
    else
      echo "[SSH] WARNING: SSH daemon failed to start"
    fi

    # ── 8. Display connection info ──
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SSH] CONNECTION INFO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Connect:  ssh -p ${local.ssh_port} coder@${var.host_ip}"
    echo "  Password: ${var.password}"
    echo ""
    echo "  Git SSH auth is handled by Coder natively via \$GIT_SSH_COMMAND"
    echo "  Add your Coder SSH key (from profile) to GitHub/GitLab/Gitea"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "ssh_port" {
  description = "External SSH port (publish this from the Docker container)"
  value       = local.ssh_port
}

output "internal_port" {
  description = "Internal SSH port inside the container (sshd listens here)"
  value       = local.internal_port
}

output "connection_command" {
  description = "SSH connection command for display"
  value       = "ssh -p ${local.ssh_port} coder@${var.host_ip}"
}
