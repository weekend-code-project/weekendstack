# =============================================================================
# MODULE: Git Identity
# =============================================================================
# DESCRIPTION:
#   Configures Git with the workspace owner's name and email for commits and
#   marks the workspace folder as safe.
#
# USAGE:
#   This module outputs a shell script that should be included in the
#   coder_agent startup_script.
#
# OUTPUTS:
#   - setup_script: Shell script to configure git identity
# =============================================================================

output "setup_script" {
  description = "Shell script to configure git identity and SSH keys"
  value       = <<-EOT
    echo "[GIT-IDENTITY] Configuring Git identity..."
    git config --global user.name "${var.git_author_name}"
    git config --global user.email "${var.git_author_email}"
    git config --global --add safe.directory /home/coder/workspace
    echo "[GIT-IDENTITY] ✅ Git identity configured"
    
    echo "[GIT-IDENTITY] Setting up SSH keys from /mnt/host-ssh..."
    
    # Create .ssh directory with proper permissions
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Copy SSH keys from mounted directory (if any exist)
    if [ -n "$(ls -A /mnt/host-ssh 2>/dev/null)" ]; then
      cp -r /mnt/host-ssh/* ~/.ssh/ 2>/dev/null || true
      chmod 600 ~/.ssh/id_* 2>/dev/null || true
      chmod 644 ~/.ssh/id_*.pub 2>/dev/null || true
      chmod 600 ~/.ssh/config 2>/dev/null || true
      echo "[GIT-IDENTITY] ✅ SSH keys copied from host"
    else
      echo "[GIT-IDENTITY] ℹ️  No SSH keys found at /mnt/host-ssh - generate with: ssh-keygen -t ed25519"
    fi
    
    # Create known_hosts and add common Git hosting services
    touch ~/.ssh/known_hosts
    chmod 644 ~/.ssh/known_hosts
    echo "[GIT-IDENTITY] Adding known hosts for Git services..."
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H gitlab.com >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null || true
    echo "[GIT-IDENTITY] ✅ SSH setup complete"
  EOT
}
