# =============================================================================
# NODE TEMPLATE
# =============================================================================
# A full-featured Node.js development workspace.
#
# Features:
#   - Configurable Node.js version (via NVM by default)
#   - Package manager selection (npm/pnpm/yarn)
#   - Optional global tooling (TypeScript, ESLint, http-server)
#   - Optional node_modules persistence (separate volume)
#   - Auto npm install on startup when package.json is present
#   - Git integration + repo cloning
#   - SSH server access
#   - External preview via Traefik
#   - Code-server web IDE
#
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

# =============================================================================
# PROVIDERS
# =============================================================================

provider "docker" {}

# =============================================================================
# CODER DATA SOURCES
# =============================================================================

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

data "coder_external_auth" "github" {
  count    = var.github_external_auth ? 1 : 0
  id       = "github"
  optional = true
}

# =============================================================================
# PARAMETERS
# =============================================================================

data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node.js Version"
  description  = "Select the Node.js version to install"
  type         = "string"
  default      = "lts"
  mutable      = false
  order        = 10

  option {
    name  = "LTS (Recommended)"
    value = "lts"
  }
  option {
    name  = "Node 22"
    value = "22"
  }
  option {
    name  = "Node 20"
    value = "20"
  }
  option {
    name  = "Node 18"
    value = "18"
  }
  option {
    name  = "Latest"
    value = "latest"
  }
}

data "coder_parameter" "package_manager" {
  name         = "package_manager"
  display_name = "Package Manager"
  description  = "Package manager for installing dependencies"
  type         = "string"
  default      = "npm"
  mutable      = false
  order        = 11

  option {
    name  = "npm"
    value = "npm"
  }
  option {
    name  = "pnpm"
    value = "pnpm"
  }
  option {
    name  = "yarn"
    value = "yarn"
  }
}

data "coder_parameter" "persist_node_modules" {
  name         = "persist_node_modules"
  display_name = "Persist node_modules"
  description  = "Store node_modules in a separate volume to keep workspace lean. Useful when home is on a small drive."
  type         = "bool"
  default      = "false"
  mutable      = false
  order        = 12
}

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run after workspace is ready (e.g., 'npm run dev -- --host 0.0.0.0 --port 8080')"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 100
}

data "coder_parameter" "preview_port" {
  name         = "preview_port"
  display_name = "Preview Port"
  description  = "Port for the dev server"
  type         = "number"
  default      = "8080"
  mutable      = true
  order        = 101
}

data "coder_parameter" "external_preview" {
  name         = "external_preview"
  display_name = "External Preview"
  description  = "Enable external preview via Traefik"
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 200
}

data "coder_parameter" "workspace_password" {
  name         = "workspace_password"
  display_name = "Workspace Password"
  description  = "Password for SSH and external preview. Empty = auto-generated for SSH."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 201
}

data "coder_parameter" "enable_ssh" {
  name         = "enable_ssh"
  display_name = "Enable SSH"
  description  = "Start SSH server for remote access"
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 300
}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository URL"
  description  = "Git repository to clone (SSH or HTTPS). Leave empty to skip."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 400
}

data "coder_parameter" "git_cli" {
  name         = "git_cli"
  display_name = "Git Platform CLI"
  description  = "Install a CLI for your Git platform"
  type         = "string"
  default      = "none"
  mutable      = true
  order        = 401

  option {
    name  = "None"
    value = "none"
  }
  option {
    name  = "GitHub (gh)"
    value = "github"
  }
  option {
    name  = "GitLab (glab)"
    value = "gitlab"
  }
  option {
    name  = "Gitea (tea)"
    value = "gitea"
  }
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  workspace_name   = lower(data.coder_workspace.me.name)
  owner_name       = data.coder_workspace_owner.me.name
  container_name   = "coder-${local.owner_name}-${local.workspace_name}"
  workspace_folder = "/home/coder/workspace"
  docker_image     = "codercom/enterprise-base:ubuntu"

  node_version     = data.coder_parameter.node_version.value
  package_manager  = data.coder_parameter.package_manager.value
  persist_nm       = data.coder_parameter.persist_node_modules.value

  startup_command          = data.coder_parameter.startup_command.value
  preview_port             = data.coder_parameter.preview_port.value
  external_preview_enabled = data.coder_parameter.external_preview.value
  workspace_password       = data.coder_parameter.workspace_password.value
  ssh_enabled              = data.coder_parameter.enable_ssh.value
  ssh_password             = local.workspace_password != "" ? local.workspace_password : random_password.ssh_fallback.result
  ssh_port                 = try(module.ssh_server[0].ssh_port, 0)

  git_cli     = data.coder_parameter.git_cli.value
  gitlab_host = var.gitlab_host
}

# =============================================================================
# AUTO-GENERATED SSH PASSWORD
# =============================================================================

resource "random_password" "ssh_fallback" {
  length  = 16
  special = false
}

# =============================================================================
# DOCKER IMAGE
# =============================================================================

data "docker_registry_image" "workspace" {
  name = local.docker_image
}

resource "docker_image" "workspace" {
  name          = data.docker_registry_image.workspace.name
  pull_triggers = [data.docker_registry_image.workspace.sha256_digest]
  keep_locally  = true
}

# =============================================================================
# PERSISTENT STORAGE
# =============================================================================

resource "docker_volume" "home" {
  name = "coder-${local.owner_name}-${local.workspace_name}-home"
}

# =============================================================================
# CODER AGENT
# =============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = local.workspace_folder

  startup_script = <<-SCRIPT
    #!/bin/bash
    set -e

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP] Node.js workspace initialization..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # First-time home init
    if [ ! -f "$HOME/.init_done" ]; then
      echo "[STARTUP] First startup, initializing home..."
      cp -rT /etc/skel "$HOME" 2>/dev/null || true
      mkdir -p "$HOME/workspace" "$HOME/.config" "$HOME/.local/bin"
      chmod 755 "$HOME/workspace"
      if ! grep -q "cd ~/workspace" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "cd ~/workspace 2>/dev/null || true" >> "$HOME/.bashrc"
      fi
      touch "$HOME/.init_done"
    fi

    mkdir -p "${local.workspace_folder}"
    echo "[STARTUP] Environment ready"
  SCRIPT

  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
    interval     = 5
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage"
    key          = "memory"
    script       = "free -m | awk 'NR==2{printf \"%.1f%%\", $3*100/$2}'"
    interval     = 5
    timeout      = 1
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk"
    script       = "df -h /home/coder | awk 'NR==2{print $5}'"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Node.js"
    key          = "node"
    script       = "node -v 2>/dev/null || echo 'Installing...'"
    interval     = 10
    timeout      = 2
  }

  metadata {
    display_name = "SSH"
    key          = "ssh"
    script       = local.ssh_enabled ? "if pgrep sshd >/dev/null; then echo 'Port ${local.ssh_port}'; else echo 'Starting...'; fi" : "echo 'Disabled'"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Git Repo"
    key          = "git_repo"
    script       = "cd /home/coder/workspace 2>/dev/null && git remote get-url origin 2>/dev/null | sed 's|.*[:/]||;s|\\.git$||' | grep . || echo 'None'"
    interval     = 60
    timeout      = 2
  }
}

# =============================================================================
# CODE SERVER (Web IDE)
# =============================================================================

module "code_server" {
  source   = "./modules/feature/code-server"
  agent_id = coder_agent.main.id
  folder   = local.workspace_folder
  order    = 1
}

# =============================================================================
# NODE VERSION
# =============================================================================

module "node_version" {
  source = "./modules/feature/node-version"

  agent_id         = coder_agent.main.id
  install_strategy = "nvm"
  node_version     = local.node_version
  package_manager  = local.package_manager
}

# =============================================================================
# NODE TOOLING (optional global packages)
# =============================================================================

module "node_tooling" {
  source = "./modules/feature/node-tooling"

  agent_id          = coder_agent.main.id
  enable_typescript = true
  package_manager   = local.package_manager
}

# =============================================================================
# NODE MODULES PERSISTENCE (optional)
# =============================================================================

module "node_modules_persist" {
  source = "./modules/feature/node-modules-persist"

  agent_id           = coder_agent.main.id
  workspace_name     = local.workspace_name
  owner_name         = local.owner_name
  workspace_folder   = local.workspace_folder
  node_modules_paths = "node_modules"
  enabled            = local.persist_nm
}

# =============================================================================
# TRAEFIK ROUTING
# =============================================================================

module "traefik_routing" {
  source                   = "./modules/feature/traefik-routing"
  agent_id                 = coder_agent.main.id
  workspace_name           = local.workspace_name
  workspace_owner          = local.owner_name
  workspace_owner_id       = data.coder_workspace_owner.me.id
  workspace_id             = data.coder_workspace.me.id
  base_domain              = var.base_domain
  preview_port             = local.preview_port
  external_preview_enabled = local.external_preview_enabled
  workspace_password       = local.workspace_password
}

# =============================================================================
# SSH SERVER
# =============================================================================

module "ssh_server" {
  count  = local.ssh_enabled ? 1 : 0
  source = "./modules/feature/ssh-server"

  agent_id       = coder_agent.main.id
  workspace_id   = data.coder_workspace.me.id
  workspace_name = local.workspace_name
  password       = local.ssh_password
  host_ip        = var.host_ip
}

# =============================================================================
# GIT CONFIGURATION + REPOSITORY CLONE
# =============================================================================

module "git_config" {
  source = "./modules/feature/git-config"

  agent_id            = coder_agent.main.id
  owner_name          = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  owner_email         = data.coder_workspace_owner.me.email
  workspace_folder    = local.workspace_folder
  repo_url            = data.coder_parameter.repo_url.value
  github_access_token = try(data.coder_external_auth.github[0].access_token, "")
}

# =============================================================================
# GIT PLATFORM CLI
# =============================================================================

module "git_platform_cli" {
  count  = local.git_cli != "none" ? 1 : 0
  source = "./modules/feature/git-platform-cli"

  agent_id    = coder_agent.main.id
  git_cli     = local.git_cli
  gitlab_host = local.gitlab_host
}

# =============================================================================
# LOCAL PREVIEW
# =============================================================================

resource "coder_app" "local_preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Local Preview"
  icon         = "/icon/widgets.svg"
  url          = "http://localhost:${local.preview_port}"
  subdomain    = false
  share        = "owner"
  order        = 10

  healthcheck {
    url       = "http://localhost:${local.preview_port}"
    interval  = 5
    threshold = 3
  }
}

# =============================================================================
# STARTUP COMMAND (npm install + user command)
# =============================================================================

resource "coder_script" "startup_command" {
  agent_id           = coder_agent.main.id
  display_name       = "Startup Command"
  icon               = "/icon/play.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-SCRIPT
    #!/bin/bash

    STARTUP_CMD="${local.startup_command}"
    WORKSPACE_DIR="${local.workspace_folder}"
    LOG_FILE="/tmp/startup-server.log"
    PID_FILE="/tmp/startup-server.pid"
    PREVIEW_PORT="${local.preview_port}"
    WORKSPACE_NAME="${local.workspace_name}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP-CMD] Node.js Workspace Startup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for Node.js to be available (node-version module must finish)
    echo "[STARTUP-CMD] Waiting for Node.js..."
    MAX_WAIT=180
    WAITED=0
    while ! command -v node >/dev/null 2>&1; do
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[STARTUP-CMD] WARNING: Node.js not available after $${MAX_WAIT}s"
        break
      fi
      sleep 2
      WAITED=$((WAITED + 2))
      # Source NVM if present
      if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        \. "$NVM_DIR/nvm.sh"
      fi
    done

    if command -v node >/dev/null 2>&1; then
      echo "[STARTUP-CMD] Node: $(node -v), npm: $(npm -v 2>/dev/null || echo 'n/a')"
    fi

    cd "$WORKSPACE_DIR" 2>/dev/null || { mkdir -p "$WORKSPACE_DIR"; cd "$WORKSPACE_DIR"; }

    # Auto npm install if package.json exists and node_modules is empty/missing
    if [ -f "$WORKSPACE_DIR/package.json" ]; then
      if [ ! -d "$WORKSPACE_DIR/node_modules" ] || [ -z "$(ls -A "$WORKSPACE_DIR/node_modules" 2>/dev/null | head -1)" ]; then
        echo "[STARTUP-CMD] Running dependency install..."
        if [ -f "$WORKSPACE_DIR/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
          pnpm install 2>&1 || true
        elif [ -f "$WORKSPACE_DIR/yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
          yarn install 2>&1 || true
        elif [ -f "$WORKSPACE_DIR/package-lock.json" ]; then
          npm ci 2>&1 || npm install 2>&1 || true
        else
          npm install 2>&1 || true
        fi
        echo "[STARTUP-CMD] Dependencies installed"
      else
        echo "[STARTUP-CMD] node_modules already populated (skipping install)"
      fi
    fi

    if [ -z "$STARTUP_CMD" ]; then
      echo "[STARTUP-CMD] No startup command configured"
      exit 0
    fi

    echo "[STARTUP-CMD] Command: $STARTUP_CMD"

    # Kill previous server
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE")
      kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi

    nohup bash -c "cd '$WORKSPACE_DIR' && $STARTUP_CMD" > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo $SERVER_PID > "$PID_FILE"
    sleep 3

    if kill -0 $SERVER_PID 2>/dev/null; then
      echo "[STARTUP-CMD] Server started (PID: $SERVER_PID)"
    else
      echo "[STARTUP-CMD] Server may have failed. Check $LOG_FILE"
      tail -5 "$LOG_FILE" 2>/dev/null || true
    fi
  SCRIPT
}

# =============================================================================
# WORKSPACE CONTAINER
# =============================================================================

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  name     = local.container_name
  image    = docker_image.workspace.image_id
  hostname = local.workspace_name

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]

  networks_advanced {
    name = "coder-network"
  }

  # Traefik labels
  dynamic "labels" {
    for_each = module.traefik_routing.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  # SSH port
  dynamic "ports" {
    for_each = try([module.ssh_server[0].ssh_port], [])
    content {
      internal = try(module.ssh_server[0].internal_port, 2222)
      external = ports.value
    }
  }

  labels {
    label = "glance.hide"
    value = "true"
  }

  # Home directory
  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
  }

  # Node modules persistent volume (when enabled)
  dynamic "volumes" {
    for_each = module.node_modules_persist.enabled ? [1] : []
    content {
      volume_name    = module.node_modules_persist.volume_name
      container_path = module.node_modules_persist.volume_mount_path
    }
  }

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  stdin_open = true
  tty        = true
  memory     = 2048

  lifecycle {
    ignore_changes = [image]
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "workspace_name" {
  value = local.workspace_name
}

output "container_name" {
  value = local.container_name
}
