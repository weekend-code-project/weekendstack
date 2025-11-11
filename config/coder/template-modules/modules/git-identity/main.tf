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
    # Configure Git identity
    git config --global user.name "${var.git_author_name}" >/dev/null 2>&1
    git config --global user.email "${var.git_author_email}" >/dev/null 2>&1
    git config --global --add safe.directory /home/coder/workspace >/dev/null 2>&1
    
    # Setup SSH keys
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Copy SSH keys from mounted directory (if any exist)
    if [ -n "$(ls -A /mnt/host-ssh 2>/dev/null)" ]; then
      cp -r /mnt/host-ssh/* ~/.ssh/ 2>/dev/null || true
      chmod 600 ~/.ssh/id_* 2>/dev/null || true
      chmod 644 ~/.ssh/id_*.pub 2>/dev/null || true
      chmod 600 ~/.ssh/config 2>/dev/null || true
      
      # Count keys for verification
      KEY_COUNT=$(ls ~/.ssh/id_* 2>/dev/null | grep -v ".pub" | wc -l)
      echo "[GIT-IDENTITY] ✅ Configured (SSH keys: $KEY_COUNT)"
    else
      echo "[GIT-IDENTITY] ⚠️  No SSH keys found - git clone via SSH will fail"
    fi
    
    # Add known hosts silently
    touch ~/.ssh/known_hosts
    chmod 644 ~/.ssh/known_hosts
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H gitlab.com >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null || true
    
    # Try adding Gitea hosts silently
    for gitea_host in git.weekendcodeproject.dev gitea 192.168.1.50; do
      timeout 2 ssh-keyscan -H -p 2222 "$gitea_host" >> ~/.ssh/known_hosts 2>/dev/null || true
    done
  EOT
}
