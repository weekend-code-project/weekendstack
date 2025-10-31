# =============================================================================
# MODULE: Git Integration
# =============================================================================
# Provides Git repository cloning functionality with user parameters and SSH
# key generation for GitHub/GitLab access.

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

# SSH Key Setup Script
output "ssh_key_setup_script" {
  description = "Script to generate SSH key if not present"
  value       = <<-EOT
    echo "[GIT] Setting up SSH key for Git operations..."
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
    
    if [ -f "$SSH_KEY_PATH" ]; then
      echo "[GIT] SSH key already exists at $SSH_KEY_PATH"
    else
      echo "[GIT] Generating new SSH key..."
      mkdir -p "$HOME/.ssh"
      ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "coder-workspace"
      chmod 600 "$SSH_KEY_PATH"
      chmod 644 "$SSH_KEY_PATH.pub"
      echo "[GIT] ✅ SSH key generated at $SSH_KEY_PATH"
    fi
    
    # Ensure GitHub is in known_hosts
    if ! grep -q "github.com" "$HOME/.ssh/known_hosts" 2>/dev/null; then
      mkdir -p "$HOME/.ssh"
      ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
      echo "[GIT] Added github.com to known_hosts"
    fi
    
    echo "[GIT] Public key:"
    cat "$SSH_KEY_PATH.pub"
    echo ""
    echo "[GIT] Add this key to GitHub: https://github.com/settings/keys"
  EOT
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

# Metadata for SSH public key
output "ssh_key_metadata" {
  description = "Metadata block showing SSH public key"
  value       = <<-EOT
    {
      "key": "git_ssh_public_key",
      "display_name": "Git SSH Public Key",
      "value": "$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'Not yet generated - restart workspace')",
      "icon": "/icon/git.svg",
      "sensitive": false
    }
  EOT
}
