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
      echo "[GIT] Existing repo detected; skipping clone."
    else
      echo "[GIT] Cloning $REPO into $WSDIR..."
      MIR="/tmp/repo-mirror"; WRK="/tmp/repo-work"
      rm -rf "$MIR" "$WRK"

      # Configure Git to use SSH and skip host key checking for first-time connections
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/home/coder/.ssh/known_hosts"
      
      # Try a mirror clone for speed/reliability, fall back to direct clone
      if git clone --mirror "$REPO" "$MIR" 2>&1 | grep -v "Cloning into"; then
        if ! git clone "$MIR" "$WRK" 2>&1 | grep -v "Cloning into"; then
          echo "[GIT] Mirror present but working clone failed; trying direct clone"
          rm -rf "$WRK"
          if ! git clone "$REPO" "$WRK" 2>&1 | grep -v "Cloning into"; then
            echo "[GIT] ❌ Clone failed - check repository URL and access permissions"
          fi
        fi
      else
        echo "[GIT] Mirror clone failed; trying direct clone"
        if ! git clone "$REPO" "$WRK" 2>&1 | grep -v "Cloning into"; then
          echo "[GIT] ❌ Clone failed - check repository URL and access permissions"
        fi
      fi

      if [ -d "$WRK/.git" ]; then
        (
          cd "$WRK" || exit 0
          # Ensure origin is the real repo URL
          git remote set-url origin "$REPO" >/dev/null 2>&1 || true
          git fetch origin --prune --tags >/dev/null 2>&1 || true
          DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@' || echo main)
          # Prefer checking out the remote default branch if it exists
          git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 || git checkout -B "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
          git submodule update --init --recursive >/dev/null 2>&1 || true
          
          # Fetch all remote branches and create local tracking branches
          echo "[GIT] Fetching all remote branches..."
          git fetch --all >/dev/null 2>&1 || true
          for branch in $(git branch -r | grep -v '\->' | grep -v HEAD | sed 's/origin\///'); do
            git branch --track "$branch" "origin/$branch" 2>/dev/null || true
          done
        )

        # Create workspace dir and copy repo contents in, even if non-empty
        mkdir -p "$WSDIR"
        # Use tar streaming to avoid needing rsync; preserves dotfiles and perms
        tar -C "$WRK" -cf - . | tar -C "$WSDIR" -xf -
        echo "[GIT] ✅ Repo synced to $WSDIR (all branches available locally)"
      else
        echo "[GIT] Clone failed; skipping"
      fi
    fi
  EOT
}
