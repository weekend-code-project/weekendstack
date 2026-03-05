# =============================================================================
# DOCKER TEMPLATE
# =============================================================================
# A Docker-in-Docker workspace template for container development.
#
# Features:
#   - Privileged container with Docker-in-Docker support
#   - Code-server web IDE
#   - SSH server access
#   - External preview via Traefik
#   - Default web server for hosting
#
# This template does NOT include:
#   - Git integration (pure Docker workspace)
#   - Node.js / language-specific tooling
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

# =============================================================================
# PARAMETERS
# =============================================================================

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run after workspace is ready. Runs in /home/coder/workspace."
  type         = "string"
  default      = "python3 -m http.server 8080"
  mutable      = true
  order        = 100
}

data "coder_parameter" "preview_port" {
  name         = "preview_port"
  display_name = "Preview Port"
  description  = "Port for the preview server"
  type         = "number"
  default      = "8080"
  mutable      = true
  order        = 101
}

data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Auto-Generate HTML"
  description  = "Generate a default index.html if none exists"
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 102
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

# =============================================================================
# LOCALS
# =============================================================================

locals {
  workspace_name   = lower(data.coder_workspace.me.name)
  owner_name       = data.coder_workspace_owner.me.name
  container_name   = "coder-${local.owner_name}-${local.workspace_name}"
  workspace_folder = "/home/coder/workspace"
  docker_image     = "codercom/enterprise-base:ubuntu"

  startup_command          = data.coder_parameter.startup_command.value
  preview_port             = data.coder_parameter.preview_port.value
  auto_generate_html       = data.coder_parameter.auto_generate_html.value
  external_preview_enabled = data.coder_parameter.external_preview.value
  workspace_password       = data.coder_parameter.workspace_password.value
  ssh_enabled              = data.coder_parameter.enable_ssh.value
  ssh_password             = local.workspace_password != "" ? local.workspace_password : random_password.ssh_fallback.result
  ssh_port                 = try(module.ssh_server[0].ssh_port, 0)
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
    echo "[STARTUP] Docker workspace initialization..."
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

    # ── Install Docker CLI + daemon for DinD ──
    if ! command -v docker >/dev/null 2>&1; then
      echo "[STARTUP] Installing Docker for DinD..."
      (
        flock -w 300 9 || true
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y -qq ca-certificates curl gnupg >/dev/null 2>&1
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[STARTUP] Docker installed"
    fi

    # Ensure docker group exists and coder is a member BEFORE starting daemon
    sudo groupadd -f docker 2>/dev/null || true
    sudo usermod -aG docker coder 2>/dev/null || true

    # Start Docker daemon
    if ! sudo pgrep -x dockerd >/dev/null 2>&1; then
      echo "[STARTUP] Starting Docker daemon..."
      sudo sh -c 'dockerd > /tmp/dockerd.log 2>&1 &'
      # Wait for Docker to be ready
      WAITED=0
      while ! sudo docker info >/dev/null 2>&1; do
        sleep 1
        WAITED=$((WAITED + 1))
        if [ $WAITED -ge 60 ]; then
          echo "[STARTUP] WARNING: Docker daemon not ready after 60s"
          echo "[STARTUP] dockerd log tail:"
          tail -20 /tmp/dockerd.log 2>/dev/null || true
          break
        fi
      done
      if sudo docker info >/dev/null 2>&1; then
        # Fix socket permissions so coder user can access without sudo
        sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        echo "[STARTUP] Docker daemon ready"
      fi
    fi

    echo "[STARTUP] User: $(whoami)"
    echo "[STARTUP] Docker: $(docker --version 2>/dev/null || echo 'not available')"
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
    display_name = "Docker"
    key          = "docker"
    script       = "docker info --format '{{.ContainersRunning}} containers' 2>/dev/null || echo 'Not running'"
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
# STARTUP COMMAND
# =============================================================================

resource "coder_script" "startup_command" {
  agent_id           = coder_agent.main.id
  display_name       = "Startup Command"
  icon               = "/icon/desktop.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-SCRIPT
    #!/bin/bash

    STARTUP_CMD="${local.startup_command}"
    WORKSPACE_DIR="${local.workspace_folder}"
    LOG_FILE="/tmp/startup-server.log"
    PID_FILE="/tmp/startup-server.pid"
    PREVIEW_PORT="${local.preview_port}"
    AUTO_HTML="${local.auto_generate_html}"
    WORKSPACE_NAME="${local.workspace_name}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP-CMD] Docker Workspace Startup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -z "$STARTUP_CMD" ]; then
      echo "[STARTUP-CMD] No command configured (skipping)"
      exit 0
    fi

    # Wait for code-server
    echo "[STARTUP-CMD] Waiting for code-server..."
    MAX_WAIT=60
    WAITED=0
    while [ $WAITED -lt $MAX_WAIT ]; do
      if pgrep -f "code-server" > /dev/null 2>&1; then break; fi
      if [ -f /tmp/code-server.log ] && grep -q "HTTP server listening" /tmp/code-server.log 2>/dev/null; then break; fi
      sleep 2
      WAITED=$((WAITED + 2))
    done

    mkdir -p "$WORKSPACE_DIR"
    cd "$WORKSPACE_DIR"

    # Auto-generate HTML
    if [ "$AUTO_HTML" = "true" ] && [ ! -f "$WORKSPACE_DIR/index.html" ]; then
      echo "[STARTUP-CMD] Generating default index.html..."
      cat > "$WORKSPACE_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Docker Workspace</title>
    <style>
        body { font-family: -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; background: linear-gradient(135deg, #1a1a2e, #16213e); color: #fff; margin: 0; }
        .container { background: rgba(255,255,255,0.1); padding: 40px; border-radius: 16px; text-align: center; backdrop-filter: blur(10px); }
        h1 { font-size: 2em; margin-bottom: 10px; }
        .badge { background: #00d4aa; color: #000; padding: 8px 16px; border-radius: 20px; display: inline-block; margin: 15px 0; font-weight: 600; }
        .info { text-align: left; margin-top: 20px; }
        .info div { padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.1); }
        code { background: rgba(255,255,255,0.15); padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Docker Workspace</h1>
        <div class="badge">Docker-in-Docker Ready</div>
        <div class="info">
            <div>Container: <code>active</code></div>
            <div>DinD: <code>enabled</code></div>
        </div>
    </div>
</body>
</html>
HTMLEOF
    fi

    echo "[STARTUP-CMD] Command: $STARTUP_CMD"

    # Kill previous server
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE")
      kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi

    nohup bash -c "$STARTUP_CMD" > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo $SERVER_PID > "$PID_FILE"
    sleep 2

    if kill -0 $SERVER_PID 2>/dev/null; then
      echo "[STARTUP-CMD] Server started (PID: $SERVER_PID)"
    else
      echo "[STARTUP-CMD] Server may have failed. Check $LOG_FILE"
    fi
  SCRIPT
}

# =============================================================================
# WORKSPACE CONTAINER
# =============================================================================

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  name       = local.container_name
  image      = docker_image.workspace.image_id
  hostname   = local.workspace_name
  privileged = true  # Required for Docker-in-Docker

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

  # Docker socket persistence (DinD data survives restarts)
  volumes {
    volume_name    = docker_volume.docker_data.name
    container_path = "/var/lib/docker"
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
  memory     = 4096  # 4GB for DinD workloads

  lifecycle {
    ignore_changes = [image]
  }
}

# Docker data volume (persists DinD images/containers across restarts)
resource "docker_volume" "docker_data" {
  name = "coder-${local.owner_name}-${local.workspace_name}-docker"
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
