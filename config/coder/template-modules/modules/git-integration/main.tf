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
      echo "[GIT] No repository URL provided; skipping clone."
    elif [ -d "$WSDIR/.git" ]; then
      echo "[GIT] ✓ Existing repository detected at $WSDIR; skipping clone."
    else
      echo "[GIT] Repository: $REPO"
      
      # Detect repository hosting service for CLI info
      if echo "$REPO" | grep -qiE "github\.com"; then
        echo "[GIT] ℹ️  Detected GitHub repository - GitHub CLI (gh) will be installed"
      elif echo "$REPO" | grep -qiE "gitea|git\.weekendcodeproject\.dev"; then
        echo "[GIT] ℹ️  Detected Gitea repository - Gitea CLI (tea) will be installed"
      elif echo "$REPO" | grep -qiE "gitlab\.com"; then
        echo "[GIT] ℹ️  Detected GitLab repository - no CLI auto-installation (not supported yet)"
      elif echo "$REPO" | grep -qiE "bitbucket\.org"; then
        echo "[GIT] ℹ️  Detected Bitbucket repository - no CLI auto-installation (not supported yet)"
      else
        echo "[GIT] ℹ️  Unknown repository hosting service - no CLI will be installed"
      fi
      
      echo "[GIT] Cloning into $WSDIR..."
      
      # Configure Git to use SSH and skip host key checking for first-time connections
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/coder/.ssh/known_hosts"
      
      # Verify SSH access if using SSH URL
      if echo "$REPO" | grep -q "^git@"; then
        # Extract domain from git@domain:user/repo.git or git@domain:port/user/repo.git
        SSH_DOMAIN=$(echo "$REPO" | sed -n 's/git@\([^:]*\):.*/\1/p')
        
        echo "[GIT] Verifying SSH access to $SSH_DOMAIN..."
        
        # Detect if this is a local Gitea instance (common domains/IPs)
        SSH_PORT=22
        SSH_OPTS=""
        if echo "$SSH_DOMAIN" | grep -qiE "gitea|git\.weekendcodeproject\.dev|192\.168\.|localhost|127\.0\.0\.1"; then
          SSH_PORT=2222
          echo "[GIT] Detected Gitea instance, using port $SSH_PORT"
        fi
        
        # Test SSH connection
        # GitHub/GitLab/Bitbucket respond with welcome messages
        # Gitea also responds with authentication confirmation
        if ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=5 -p $SSH_PORT -T "git@$SSH_DOMAIN" 2>&1 | grep -qiE "successfully authenticated|welcome|hi|gitea"; then
          echo "[GIT] ✅ SSH authentication successful to $SSH_DOMAIN:$SSH_PORT"
        else
          echo "[GIT] ❌ SSH authentication failed to $SSH_DOMAIN:$SSH_PORT"
          echo "[GIT] Attempting manual SSH test..."
          ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=5 -p $SSH_PORT -T "git@$SSH_DOMAIN" 2>&1 | head -5
          echo "[GIT] SSH keys location: ~/.ssh/"
          ls -la ~/.ssh/ 2>/dev/null || echo "[GIT] No SSH keys found!"
          echo "[GIT] Host mount: /mnt/host-ssh/"
          ls -la /mnt/host-ssh/ 2>/dev/null || echo "[GIT] No host SSH keys found!"
          exit 0
        fi
        
        # Update GIT_SSH_COMMAND with correct port for Gitea
        if [ "$SSH_PORT" != "22" ]; then
          export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/coder/.ssh/known_hosts -p $SSH_PORT"
        fi
      fi
      
      # Create workspace directory if it doesn't exist
      mkdir -p "$WSDIR"
      
      # Clone directly into workspace directory
      if git clone "$REPO" "$WSDIR" 2>&1 | tee /tmp/git-clone.log; then
        cd "$WSDIR" || exit 0
        
        # Get default branch
        DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
        if [ -z "$DEFAULT_BRANCH" ]; then
          DEFAULT_BRANCH=$(git branch --show-current)
        fi
        [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
        
        echo "[GIT] On branch: $DEFAULT_BRANCH"
        
        # Initialize submodules if any
        if [ -f ".gitmodules" ]; then
          echo "[GIT] Initializing submodules..."
          git submodule update --init --recursive >/dev/null 2>&1 || true
        fi
        
        # Fetch all remote branches
        echo "[GIT] Fetching all remote branches..."
        git fetch --all >/dev/null 2>&1 || true
        
        # Create local tracking branches for all remote branches
        for branch in $(git branch -r | grep -v '\->' | grep -v HEAD | sed 's/origin\///'); do
          git branch --track "$branch" "origin/$branch" 2>/dev/null || true
        done
        
        echo "[GIT] ✅ Repository cloned to $WSDIR (all branches available)"
      else
        echo "[GIT] ❌ Clone failed - check repository URL and access permissions"
        echo "[GIT] Log saved to /tmp/git-clone.log"
      fi
    fi
  EOT
}
