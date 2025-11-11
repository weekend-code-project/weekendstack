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
      echo "[GIT] No repo configured; skipping clone."
    elif [ -d "$WSDIR/.git" ]; then
      echo "[GIT] ✓ Existing repo detected at $WSDIR; skipping clone."
    else
      echo "[GIT] Cloning $REPO into $WSDIR..."
      
      # Configure Git to use SSH and skip host key checking for first-time connections
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/coder/.ssh/known_hosts"
      
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
