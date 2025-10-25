# =============================================================================
# MODULE: Git Integration
# =============================================================================
# Provides Git repository cloning functionality with user parameters.

# Coder Parameter for GitHub repository
resource "coder_parameter" "github_repo" {
  name         = "github_repo"
  display_name = "GitHub Repository"
  description  = "Git repository URL to clone (e.g., git@github.com:user/repo.git). Leave empty to skip cloning."
  type         = "string"
  default      = var.github_repo_default
  mutable      = true
  order        = 10
}

# Git Clone Script
output "clone_script" {
  description = "Script to clone repository into workspace"
  value       = <<-EOT
    REPO="${coder_parameter.github_repo.value}"
    WSDIR="/home/coder/workspace"
    if [ -z "$REPO" ]; then
      echo "[GIT] No repo configured; skipping clone."
    elif [ -d "$WSDIR/.git" ]; then
      echo "[GIT] Existing repo detected; skipping clone."
    else
      echo "[GIT] Cloning $REPO into $WSDIR..."
      MIR="/tmp/repo-mirror"; WRK="/tmp/repo-work"
      rm -rf "$MIR" "$WRK"

      # Try a mirror clone for speed/reliability, fall back to direct clone
      if git clone --mirror "$REPO" "$MIR" >/dev/null 2>&1; then
        if ! git clone "$MIR" "$WRK" >/dev/null 2>&1; then
          echo "[GIT] Mirror present but working clone failed; trying direct clone"
          rm -rf "$WRK"
          git clone "$REPO" "$WRK" >/dev/null 2>&1 || true
        fi
      else
        echo "[GIT] Mirror clone failed; trying direct clone"
        git clone "$REPO" "$WRK" >/dev/null 2>&1 || true
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
        )

        # Create workspace dir and copy repo contents in, even if non-empty
        mkdir -p "$WSDIR"
        # Use tar streaming to avoid needing rsync; preserves dotfiles and perms
        tar -C "$WRK" -cf - . | tar -C "$WSDIR" -xf -
        echo "[GIT] ✅ Repo synced to $WSDIR"
      else
        echo "[GIT] Clone failed; skipping"
      fi
    fi
  EOT
}

output "repo_url" {
  description = "The configured repository URL"
  value       = coder_parameter.github_repo.value
}
