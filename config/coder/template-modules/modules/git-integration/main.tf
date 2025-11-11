# =============================================================================
# MODULE: Git Integration
# =============================================================================
# DESCRIPTION:
#   Provides Git repository cloning functionality.
#   SSH keys are handled by the ssh-integration module.
#
# USAGE:
#   This module outputs a shell script that should be included in the
#   coder_agent startup_script.
#
# OUTPUTS:
#   - clone_script: Shell script to clone repository into workspace
# =============================================================================

# Git Clone Script
output "clone_script" {
  description = "Script to clone repository into workspace"
  value       = <<-EOT
    REPO="${var.github_repo_url}"
    WSDIR="/home/coder/workspace"
    
    if [ -z "$REPO" ]; then
      # No repo configured, skip silently
      true
    elif [ -d "$WSDIR/.git" ]; then
      echo "[GIT] ✓ Repository already cloned"
    else
      # Detect hosting service
      if echo "$REPO" | grep -qiE "github\.com"; then
        CLI_INFO="(GitHub CLI will be installed)"
      elif echo "$REPO" | grep -qiE "gitea|git\.weekendcodeproject\.dev"; then
        CLI_INFO="(Gitea CLI will be installed)"
      elif echo "$REPO" | grep -qiE "gitlab\.com|bitbucket\.org"; then
        CLI_INFO="(no CLI available)"
      else
        CLI_INFO="(no CLI available)"
      fi
      
      echo "[GIT] Cloning repository $CLI_INFO"
      
      # Configure Git SSH
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/coder/.ssh/known_hosts"
      
      # Verify SSH access if using SSH URL
      if echo "$REPO" | grep -q "^git@"; then
        SSH_DOMAIN=$(echo "$REPO" | sed -n 's/git@\([^:]*\):.*/\1/p')
        SSH_PORT=22
        
        # Detect Gitea port
        if echo "$SSH_DOMAIN" | grep -qiE "gitea|git\.weekendcodeproject\.dev|192\.168\.|localhost|127\.0\.0\.1"; then
          SSH_PORT=2222
        fi
        
        # Test SSH connection
        if ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=5 -p $SSH_PORT -T "git@$SSH_DOMAIN" 2>&1 | grep -qiE "successfully authenticated|welcome|hi|gitea"; then
          echo "[GIT] ✅ SSH verified: $SSH_DOMAIN:$SSH_PORT"
        else
          echo "[GIT] ❌ SSH authentication failed: $SSH_DOMAIN:$SSH_PORT"
          echo "[GIT] Check: ls ~/.ssh/id_*"
          ls ~/.ssh/id_* 2>/dev/null || echo "[GIT] No SSH keys found!"
          exit 0
        fi
        
        # Update SSH command for Gitea port
        if [ "$SSH_PORT" != "22" ]; then
          export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/coder/.ssh/known_hosts -p $SSH_PORT"
        fi
      fi
      
      # Clone
      mkdir -p "$WSDIR"
      if git clone "$REPO" "$WSDIR" 2>&1 | grep -E "Cloning|done|error|fatal" | head -5; then
        cd "$WSDIR" || exit 0
        
        # Setup branches silently
        git fetch --all >/dev/null 2>&1 || true
        for branch in $(git branch -r 2>/dev/null | grep -v '\->' | grep -v HEAD | sed 's/origin\///' | head -10); do
          git branch --track "$branch" "origin/$branch" 2>/dev/null || true
        done
        
        # Submodules
        if [ -f ".gitmodules" ]; then
          git submodule update --init --recursive >/dev/null 2>&1 || true
        fi
        
        BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
        BRANCH_COUNT=$(git branch -r 2>/dev/null | grep -v '\->' | wc -l)
        echo "[GIT] ✅ Cloned successfully (branch: $BRANCH, $BRANCH_COUNT remote branches)"
      else
        echo "[GIT] ❌ Clone failed - check /tmp/git-clone.log"
      fi
    fi
  EOT
}
