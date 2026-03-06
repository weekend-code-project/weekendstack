# =============================================================================
# VITE TEMPLATE
# =============================================================================
# A specialized Vite + Node.js development workspace.
#
# Extends the Node template with Vite-specific defaults:
#   - Scaffolds a new Vite project if workspace is empty
#   - Configurable Vite framework (React, Vue, Svelte, Vanilla, etc.)
#   - Default startup: npm run dev -- --host 0.0.0.0 --port 8080
#   - Auto npm install on startup
#   - All Node.js features (version picker, persistence, tooling)
#   - Git integration + SSH + Traefik
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
  description  = "Node.js version for Vite development"
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
}

data "coder_parameter" "vite_framework" {
  name         = "vite_framework"
  display_name = "Vite Framework"
  description  = "Framework to scaffold when creating a new Vite project. Ignored when cloning a repo."
  type         = "string"
  default      = "vanilla"
  mutable      = false
  order        = 11

  option {
    name  = "React"
    value = "react"
  }
  option {
    name  = "React + TypeScript"
    value = "react-ts"
  }
  option {
    name  = "Vue"
    value = "vue"
  }
  option {
    name  = "Vue + TypeScript"
    value = "vue-ts"
  }
  option {
    name  = "Svelte"
    value = "svelte"
  }
  option {
    name  = "Svelte + TypeScript"
    value = "svelte-ts"
  }
  option {
    name  = "Vanilla"
    value = "vanilla"
  }
  option {
    name  = "Vanilla + TypeScript"
    value = "vanilla-ts"
  }
}

data "coder_parameter" "package_manager" {
  name         = "package_manager"
  display_name = "Package Manager"
  description  = "Package manager for installing dependencies"
  type         = "string"
  default      = "npm"
  mutable      = false
  order        = 12

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

data "coder_parameter" "node_modules_paths" {
  name         = "node_modules_paths"
  display_name = "Persist node_modules"
  description  = "Comma-separated node_modules paths to store in a separate volume (e.g. 'node_modules' or 'node_modules,frontend/node_modules'). Leave empty to disable persistence."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 13
}

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to start the dev server. Runs after dependencies are installed."
  type         = "string"
  default      = "npm run dev -- --host 0.0.0.0 --port 8080"
  mutable      = true
  order        = 14
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
  description  = "Git repo to clone (SSH or HTTPS). If set, skips Vite scaffolding."
  type         = "string"
  default      = ""
  mutable      = false
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
  vite_framework   = data.coder_parameter.vite_framework.value
  package_manager  = data.coder_parameter.package_manager.value
  nm_paths         = data.coder_parameter.node_modules_paths.value
  persist_nm       = length(trimspace(data.coder_parameter.node_modules_paths.value)) > 0
  startup_command  = data.coder_parameter.startup_command.value

  preview_port             = 8080
  external_preview_enabled = data.coder_parameter.external_preview.value
  workspace_password       = data.coder_parameter.workspace_password.value
  ssh_enabled              = data.coder_parameter.enable_ssh.value
  ssh_password             = local.workspace_password != "" ? local.workspace_password : random_password.ssh_fallback.result
  ssh_port                 = try(module.ssh_server[0].ssh_port, 0)

  git_cli     = data.coder_parameter.git_cli.value
  gitlab_host = var.gitlab_host
  repo_url    = data.coder_parameter.repo_url.value
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
    echo "[STARTUP] Vite workspace initialization..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # First-time home init
    if [ ! -f "$HOME/.init_done" ]; then
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
    display_name = "Vite Dev"
    key          = "vite"
    script       = "if pgrep -f 'vite' >/dev/null 2>&1; then echo 'Running'; else echo 'Stopped'; fi"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "SSH"
    key          = "ssh"
    script       = local.ssh_enabled ? "if pgrep sshd >/dev/null; then echo 'Port ${local.ssh_port}'; else echo 'Starting...'; fi" : "echo 'Disabled'"
    interval     = 10
    timeout      = 1
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
# NODE TOOLING
# =============================================================================

module "node_tooling" {
  source = "./modules/feature/node-tooling"

  agent_id          = coder_agent.main.id
  enable_typescript = true
  package_manager   = local.package_manager
}

# =============================================================================
# NODE MODULES PERSISTENCE
# =============================================================================

module "node_modules_persist" {
  source = "./modules/feature/node-modules-persist"

  agent_id           = coder_agent.main.id
  workspace_name     = local.workspace_name
  owner_name         = local.owner_name
  workspace_folder   = local.workspace_folder
  node_modules_paths = local.nm_paths
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
  host_ip                  = var.host_ip
  access_url               = data.coder_workspace.me.access_url
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
# GIT CONFIGURATION
# =============================================================================

module "git_config" {
  source = "./modules/feature/git-config"

  agent_id            = coder_agent.main.id
  owner_name          = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  owner_email         = data.coder_workspace_owner.me.email
  workspace_folder    = local.workspace_folder
  repo_url            = local.repo_url
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
  display_name = "Vite Preview"
  icon         = "/icon/widgets.svg"
  url          = "http://localhost:${local.preview_port}"
  subdomain    = false
  share        = "owner"
  order        = 10

  healthcheck {
    url       = "http://localhost:${local.preview_port}"
    interval  = 5
    threshold = 5
  }
}

# =============================================================================
# VITE SCAFFOLD + DEV SERVER (coder_script)
# =============================================================================

resource "coder_script" "vite_startup" {
  agent_id           = coder_agent.main.id
  display_name       = "Vite Dev Server"
  icon               = "/icon/desktop.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-SCRIPT
    #!/bin/bash

    WORKSPACE_DIR="${local.workspace_folder}"
    VITE_FRAMEWORK="${local.vite_framework}"
    STARTUP_CMD="${local.startup_command}"
    REPO_URL="${local.repo_url}"
    LOG_FILE="/tmp/vite-dev.log"
    PID_FILE="/tmp/vite-dev.pid"
    PKG_MGR="${local.package_manager}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[VITE] Vite Development Server"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for Node.js
    echo "[VITE] Waiting for Node.js..."
    MAX_WAIT=180
    WAITED=0
    while ! command -v node >/dev/null 2>&1; do
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[VITE] ERROR: Node.js not available after $${MAX_WAIT}s"
        exit 1
      fi
      sleep 2
      WAITED=$((WAITED + 2))
      if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        \. "$NVM_DIR/nvm.sh"
      fi
    done

    echo "[VITE] Node: $(node -v), npm: $(npm -v 2>/dev/null || echo 'n/a')"

    cd "$WORKSPACE_DIR"

    # ── Wait for git clone to finish (runs concurrently with this script) ──
    if [ -n "$REPO_URL" ]; then
      echo "[VITE] Waiting for repository clone to complete..."
      MAX_CLONE_WAIT=300
      CLONE_WAITED=0
      while [ ! -f /tmp/git-clone.done ] && [ $CLONE_WAITED -lt $MAX_CLONE_WAIT ]; do
        sleep 3
        CLONE_WAITED=$((CLONE_WAITED + 3))
      done
      if [ -f /tmp/git-clone.done ]; then
        echo "[VITE] Repository clone finished"
      else
        echo "[VITE] WARNING: Timed out waiting for git clone after $${MAX_CLONE_WAIT}s"
      fi
    fi

    # ── Scaffold Vite project if workspace is empty and no repo was cloned ──
    if [ -z "$REPO_URL" ] && [ ! -f "$WORKSPACE_DIR/package.json" ]; then
      echo "[VITE] Scaffolding new Vite project ($VITE_FRAMEWORK)..."

      # Create project in a temp dir then move contents
      TEMP_DIR="/tmp/vite-scaffold-$$"
      npm create vite@latest "$TEMP_DIR" -- --template "$VITE_FRAMEWORK" 2>&1 || true

      if [ -f "$TEMP_DIR/package.json" ]; then
        cp -a "$TEMP_DIR"/. "$WORKSPACE_DIR"/ 2>/dev/null || true
        rm -rf "$TEMP_DIR"
        echo "[VITE] Project scaffolded with $VITE_FRAMEWORK template"
      else
        echo "[VITE] WARNING: Vite scaffold failed, creating minimal project"
        rm -rf "$TEMP_DIR"

        # Minimal fallback
        cat > "$WORKSPACE_DIR/package.json" << 'PKGJSON'
{
  "name": "vite-workspace",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "devDependencies": {
    "vite": "^6.0.0"
  }
}
PKGJSON

        mkdir -p "$WORKSPACE_DIR/src"
        cat > "$WORKSPACE_DIR/index.html" << 'INDEXHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vite Workspace</title>
    <style>
        body { font-family: -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; background: linear-gradient(135deg, #1a1a2e, #16213e); color: #fff; margin: 0; }
        .container { background: rgba(255,255,255,0.1); padding: 40px; border-radius: 16px; text-align: center; backdrop-filter: blur(10px); }
        h1 { font-size: 2em; margin-bottom: 10px; }
        .badge { background: #68d391; color: #000; padding: 8px 16px; border-radius: 20px; display: inline-block; margin: 15px 0; font-weight: 600; }
        .info { text-align: left; margin-top: 20px; }
        .info div { padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.1); }
        code { background: rgba(255,255,255,0.15); padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Vite Workspace</h1>
        <div class="badge">Ready</div>
        <div class="info">
            <div>Edit <code>src/main.js</code> to get started</div>
            <div>Server: <code>vite dev on port 8080</code></div>
        </div>
    </div>
    <script type="module" src="/src/main.js"></script>
</body>
</html>
INDEXHTML

        cat > "$WORKSPACE_DIR/src/main.js" << 'MAINJS'
console.log('Vite dev server running');
MAINJS
      fi
    fi

    # ── Install dependencies ──
    if [ -f "$WORKSPACE_DIR/package.json" ]; then
      if [ ! -d "$WORKSPACE_DIR/node_modules" ] || [ -z "$(ls -A "$WORKSPACE_DIR/node_modules" 2>/dev/null | head -1)" ]; then
        echo "[VITE] Installing dependencies..."
        cd "$WORKSPACE_DIR"
        case "$PKG_MGR" in
          pnpm) pnpm install 2>&1 || npm install 2>&1 || true ;;
          yarn) yarn install 2>&1 || npm install 2>&1 || true ;;
          *)    npm install 2>&1 || true ;;
        esac
        echo "[VITE] Dependencies installed"
      else
        echo "[VITE] Dependencies already installed"
      fi
    fi

    # ── Start Vite dev server ──
    if [ -f "$WORKSPACE_DIR/package.json" ]; then
      echo "[VITE] Starting dev server..."

      # Kill previous server
      if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
        sleep 1
      fi

      cd "$WORKSPACE_DIR"

      # Ensure vite.config exists with allowedHosts: true (Vite 6+ blocks proxy domains)
      if [ ! -f "$WORKSPACE_DIR/vite.config.js" ] && [ ! -f "$WORKSPACE_DIR/vite.config.ts" ] && [ ! -f "$WORKSPACE_DIR/vite.config.mjs" ] && [ ! -f "$WORKSPACE_DIR/vite.config.mts" ]; then
        echo "[VITE] Creating vite.config.js with allowedHosts: true"
        cat > "$WORKSPACE_DIR/vite.config.js" << 'VITECONFIG'
import { defineConfig } from 'vite'

export default defineConfig({
  server: {
    allowedHosts: true,
  },
})
VITECONFIG
      else
        # Patch existing config if it doesn't already have allowedHosts
        for VITE_CFG in vite.config.js vite.config.ts vite.config.mjs vite.config.mts; do
          if [ -f "$WORKSPACE_DIR/$VITE_CFG" ] && ! grep -q 'allowedHosts' "$WORKSPACE_DIR/$VITE_CFG"; then
            echo "[VITE] Patching $VITE_CFG with allowedHosts: true"
            sed -i 's/server\s*:\s*{/server: { allowedHosts: true,/' "$WORKSPACE_DIR/$VITE_CFG"
            # If no server block exists, add one before the closing of defineConfig
            if ! grep -q 'allowedHosts' "$WORKSPACE_DIR/$VITE_CFG"; then
              sed -i '/defineConfig({/a\  server: { allowedHosts: true },' "$WORKSPACE_DIR/$VITE_CFG"
            fi
          fi
        done
      fi

      echo "[VITE] Command: $STARTUP_CMD"
      nohup bash -c "cd '$WORKSPACE_DIR' && $STARTUP_CMD" > "$LOG_FILE" 2>&1 &
      SERVER_PID=$!
      echo $SERVER_PID > "$PID_FILE"
      sleep 3

      if kill -0 $SERVER_PID 2>/dev/null; then
        echo "[VITE] Dev server started (PID: $SERVER_PID)"
        echo "[VITE] Local: http://localhost:8080"
      else
        echo "[VITE] Dev server failed to start. Log:"
        tail -10 "$LOG_FILE" 2>/dev/null || true
      fi
    else
      echo "[VITE] No package.json found, skipping dev server"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[VITE] Done"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

  # Node modules persistent volume
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
