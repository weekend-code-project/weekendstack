# =============================================================================
# MODULE: Git Configuration + Repository Clone
# =============================================================================
# Configures Git identity and optionally clones a repository:
#   - git config --global user.name / user.email
#   - Marks workspace folder as safe.directory
#   - Sets up GitHub OAuth credential helper (when token provided)
#   - Clones repo URL into workspace (if provided, first-time only)
#   - Mirror-clone approach (works with non-empty workspace dir)
#   - Tracks remote branches and initializes submodules
#
# Git SSH authentication is handled natively by Coder via $GIT_SSH_COMMAND.
# The user's Coder SSH key (visible in profile) must be added to GitHub/GitLab.
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
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

variable "owner_name" {
  description = "Git author/committer name (from workspace owner)"
  type        = string
}

variable "owner_email" {
  description = "Git author/committer email (from workspace owner)"
  type        = string
}

variable "workspace_folder" {
  description = "Workspace folder path (used for safe.directory and clone target)"
  type        = string
  default     = "/home/coder/workspace"
}

variable "repo_url" {
  description = "Git repository URL to clone (SSH or HTTPS). Leave empty to skip cloning."
  type        = string
  default     = ""
}

variable "github_access_token" {
  description = "GitHub OAuth access token from Coder External Auth. Empty string if not configured."
  type        = string
  default     = ""
  sensitive   = true
}

variable "coder_access_url" {
  description = "Coder server access URL (used to display SSH key settings link in error messages)"
  type        = string
  default     = ""
}

# =============================================================================
# Git Config + Clone Script
# =============================================================================

resource "coder_script" "git_config" {
  agent_id           = var.agent_id
  display_name       = "Git Config"
  icon               = "/icon/git.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-EOT
    #!/bin/bash
    set -e

    CODER_URL="${var.coder_access_url}"
    SSH_KEY_URL="$${CODER_URL:+$${CODER_URL}/settings/ssh-keys}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[GIT] Configuring Git identity and repository..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Print the current Coder SSH public key so it's easy to copy from startup logs
    # The key is per-user (shared across ALL workspaces on this Coder server)
    _CODER_SSH_KEY=$(echo "$GIT_SSH_COMMAND" | grep -oP '(?<=--agent-url )\S+' || true)
    if [ -n "$_CODER_SSH_KEY" ]; then
      : # agent URL found, key printed below
    fi
    # Attempt to read the key from coder gitssh --public-key if supported
    _PUB_KEY=$(eval "$GIT_SSH_COMMAND" --public-key 2>/dev/null || true)
    if [ -z "$_PUB_KEY" ]; then
      # Fall back: extract via ssh-add -L from coder's agent if available
      _PUB_KEY=$(SSH_AUTH_SOCK="" ssh-add -L 2>/dev/null | head -1 || true)
    fi
    if [ -n "$_PUB_KEY" ]; then
      echo "[GIT] Coder SSH public key (add this to GitHub/GitLab once):"
      echo "  $_PUB_KEY"
      [ -n "$SSH_KEY_URL" ] && echo "  Add at: $SSH_KEY_URL"
    fi

    # ── 1. Git global config ──
    git config --global user.name "${var.owner_name}" 2>/dev/null
    git config --global user.email "${var.owner_email}" 2>/dev/null
    git config --global init.defaultBranch main 2>/dev/null
    git config --global pull.rebase false 2>/dev/null
    echo "[GIT] Identity: ${var.owner_name} <${var.owner_email}>"

    # ── 2. Safe directory ──
    git config --global --add safe.directory "${var.workspace_folder}" 2>/dev/null
    echo "[GIT] Safe directory: ${var.workspace_folder}"

    # ── 3. GitHub OAuth credential helper ──
    GITHUB_TOKEN="${var.github_access_token}"
    if [ -n "$GITHUB_TOKEN" ]; then
      # Create a credential helper script that provides the OAuth token
      mkdir -p "$HOME/.local/bin"
      cat > "$HOME/.local/bin/git-credential-github-oauth" << 'CRED_HELPER'
#!/bin/bash
# Git credential helper for GitHub OAuth (managed by Coder)
# Reads from ~/.git-credentials-oauth
if [ "$1" = "get" ]; then
  input=$(cat)
  host=$(echo "$input" | grep "^host=" | cut -d= -f2)
  if [ "$host" = "github.com" ]; then
    echo "protocol=https"
    echo "host=github.com"
    echo "username=oauth2"
    cat "$HOME/.git-credentials-oauth" 2>/dev/null
  fi
fi
CRED_HELPER
      chmod +x "$HOME/.local/bin/git-credential-github-oauth"

      # Store the token securely
      echo "password=$GITHUB_TOKEN" > "$HOME/.git-credentials-oauth"
      chmod 600 "$HOME/.git-credentials-oauth"

      # Configure git to use our credential helper for github.com
      # Use credential helper chain: our helper first, then fall through
      git config --global credential.https://github.com.helper "$HOME/.local/bin/git-credential-github-oauth"
      echo "[GIT] GitHub OAuth credential helper configured (private repos enabled)"
    else
      echo "[GIT] No GitHub OAuth token (private repos need SSH keys or manual auth)"
      echo "[GIT] Tip: Set up External Auth in Coder server for automatic GitHub access"
    fi

    # ── 4. Repository clone (if URL provided and not already cloned) ──
    REPO_URL="${var.repo_url}"
    WORKSPACE_DIR="${var.workspace_folder}"

    if [ -z "$REPO_URL" ]; then
      echo "[GIT] No repository URL configured (skipping clone)"
      touch /tmp/git-clone.done
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "[GIT] Done"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      exit 0
    fi

    if [ -d "$WORKSPACE_DIR/.git" ]; then
      echo "[GIT] Repository already cloned at $WORKSPACE_DIR"
      BRANCH=$(cd "$WORKSPACE_DIR" && git branch --show-current 2>/dev/null || echo "unknown")
      REMOTE=$(cd "$WORKSPACE_DIR" && git remote get-url origin 2>/dev/null || echo "unknown")
      echo "[GIT] Branch: $BRANCH | Remote: $REMOTE"

      # Pull latest changes
      cd "$WORKSPACE_DIR"
      if git pull --ff-only 2>/dev/null; then
        echo "[GIT] Pulled latest changes"
      else
        echo "[GIT] Pull skipped (may have local changes or diverged)"
      fi

      touch /tmp/git-clone.done
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "[GIT] Done"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      exit 0
    fi

    # ── Convert GitHub SSH URL to HTTPS when OAuth token is available ──
    # If logged in via GitHub OAuth, use HTTPS + token for reliable private-repo cloning.
    # This avoids SSH key setup entirely for GitHub repos.
    if [ -n "$GITHUB_TOKEN" ] && echo "$REPO_URL" | grep -q "^git@github.com:"; then
      REPO_URL=$(echo "$REPO_URL" | sed 's|git@github.com:\(.*\)|https://github.com/\1|')
      echo "[GIT] GitHub OAuth active — cloning via HTTPS: $REPO_URL"
    fi

    # ── Pre-clone: only scan the SSH host we actually need ──
    # HTTPS clones do not need known_hosts, and broad scans can hang startup on
    # networks that block port 22 for unrelated providers.
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/known_hosts"
    chmod 644 "$HOME/.ssh/known_hosts"

    _ssh_domain=""
    if echo "$REPO_URL" | grep -q "^git@"; then
      _ssh_domain=$(echo "$REPO_URL" | sed -n 's/git@\([^:]*\):.*/\1/p')
    elif echo "$REPO_URL" | grep -q "^ssh://"; then
      _ssh_domain=$(echo "$REPO_URL" | sed -n 's#ssh://[^@]*@\([^/:]*\).*#\1#p')
      if [ -z "$_ssh_domain" ]; then
        _ssh_domain=$(echo "$REPO_URL" | sed -n 's#ssh://\([^/:]*\).*#\1#p')
      fi
    fi

    if [ -n "$_ssh_domain" ]; then
      if ! grep -q "$_ssh_domain" "$HOME/.ssh/known_hosts" 2>/dev/null; then
        echo "[GIT] Scanning host key for $_ssh_domain..."
        ssh-keyscan -T 5 -H "$_ssh_domain" >> "$HOME/.ssh/known_hosts" 2>/dev/null || \
          echo "[GIT] WARNING: Could not scan host key for $_ssh_domain"
      fi
    else
      echo "[GIT] HTTPS clone detected; skipping SSH host key scan"
    fi
    unset _ssh_domain

    echo "[GIT] Cloning: $REPO_URL"

    # ── URL type reporting ──
    if echo "$REPO_URL" | grep -q "^git@"; then
      echo "[GIT] Using Coder's native SSH key for Git authentication"
    elif echo "$REPO_URL" | grep -q "github.com" && [ -n "$GITHUB_TOKEN" ]; then
      echo "[GIT] Using GitHub OAuth token for HTTPS clone"
    else
      echo "[GIT] Using HTTPS clone (credentials may be needed for private repos)"
    fi

    # ── Clone with retry ──
    # coder gitssh can fail on first attempt during startup (timing issue)
    # Retry up to 3 times with increasing delays
    MIRROR_DIR="/tmp/repo-clone-$$"
    CLONE_SUCCESS=false
    MAX_ATTEMPTS=3

    for ATTEMPT in $(seq 1 $MAX_ATTEMPTS); do
      rm -rf "$MIRROR_DIR"
      echo "[GIT] Clone attempt $ATTEMPT/$MAX_ATTEMPTS..."

      if git clone "$REPO_URL" "$MIRROR_DIR" 2>&1; then
        CLONE_SUCCESS=true
        break
      else
        CLONE_EXIT=$?
        echo "[GIT] Clone attempt $ATTEMPT failed (exit $CLONE_EXIT)"
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
          DELAY=$((ATTEMPT * 5))
          echo "[GIT] Retrying in $${DELAY}s..."
          sleep $DELAY
        fi
      fi
    done

    # ── HTTPS fallback after SSH retries fail ──
    if [ "$CLONE_SUCCESS" = "false" ] && echo "$REPO_URL" | grep -q "^git@"; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "[GIT] SSH AUTHENTICATION FAILED"
      echo "[GIT] Your Coder SSH key is not authorized on your Git provider."
      echo "[GIT] This key is shared by ALL workspaces on this Coder server."
      echo "[GIT] Add it ONCE and every future workspace will clone automatically."
      _PUB_KEY2=$(eval "$GIT_SSH_COMMAND" --public-key 2>/dev/null || true)
      if [ -n "$_PUB_KEY2" ]; then
        echo ""
        echo "[GIT] Key to add:"
        echo "  $_PUB_KEY2"
      fi
      [ -n "$SSH_KEY_URL" ] && echo "" && echo "[GIT] Add SSH key at: $SSH_KEY_URL"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      HTTPS_URL=$(echo "$REPO_URL" | sed 's|git@\([^:]*\):\(.*\)|https://\1/\2|')
      if echo "$HTTPS_URL" | grep -qE 'https://(github\.com|gitlab\.com|bitbucket\.org)/'; then
        echo "[GIT] Trying HTTPS fallback: $HTTPS_URL"
        rm -rf "$MIRROR_DIR"
        # Unset Coder's credential interceptors so anonymous HTTPS works for public repos
        if GIT_ASKPASS="" GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="" \
           git clone "$HTTPS_URL" "$MIRROR_DIR" 2>&1; then
          CLONE_SUCCESS=true
        else
          echo "[GIT] HTTPS fallback also failed (repo is private — SSH key required)"
        fi
      fi
    fi

    if [ "$CLONE_SUCCESS" = "true" ]; then
      # Move cloned content to workspace
      mkdir -p "$WORKSPACE_DIR"
      cd "$WORKSPACE_DIR"

      # Remove existing files (preserve node_modules and .persist if present)
      find . -maxdepth 1 ! -name '.' ! -name '..' ! -name 'node_modules' ! -name '.persist' -exec rm -rf {} + 2>/dev/null || true

      mv "$MIRROR_DIR"/.git "$WORKSPACE_DIR/" 2>/dev/null || true
      mv "$MIRROR_DIR"/* "$WORKSPACE_DIR/" 2>/dev/null || true
      mv "$MIRROR_DIR"/.[!.]* "$WORKSPACE_DIR/" 2>/dev/null || true
      rm -rf "$MIRROR_DIR"

      cd "$WORKSPACE_DIR"

      # Track remote branches (up to 20)
      git fetch --all >/dev/null 2>&1 || true
      for branch in $(git branch -r 2>/dev/null | grep -v '\->' | grep -v HEAD | sed 's/origin\///' | head -20); do
        git branch --track "$branch" "origin/$branch" 2>/dev/null || true
      done

      # Initialize submodules if present
      if [ -f ".gitmodules" ]; then
        echo "[GIT] Initializing submodules..."
        git submodule update --init --recursive >/dev/null 2>&1 || true
      fi

      BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
      BRANCH_COUNT=$(git branch -r 2>/dev/null | grep -v '\->' | wc -l)
      echo "[GIT] Cloned successfully (branch: $BRANCH, $BRANCH_COUNT remote branches)"
    else
      echo "[GIT] ERROR: Repository could not be cloned"
      echo "[GIT] Repository: $REPO_URL"
      rm -rf "$MIRROR_DIR"
    fi

    # Signal to other startup scripts that git clone is done (success or failure)
    touch /tmp/git-clone.done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[GIT] Done"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "git_config_applied" {
  description = "Whether git config was applied (always true when module is used)"
  value       = true
}
