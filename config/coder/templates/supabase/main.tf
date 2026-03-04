# =============================================================================
# SUPABASE TEMPLATE
# =============================================================================
# A Supabase local development workspace using Docker-in-Docker.
#
# Uses the official Supabase CLI (`supabase start`) to spin up the full
# Supabase stack inside a privileged DinD container. This is the officially
# supported local dev setup and handles all service orchestration, versioning,
# and configuration automatically.
#
# Features:
#   - Full Supabase stack (Postgres, Studio, Auth, PostgREST, Realtime, Storage)
#   - Supabase Studio dashboard for visual DB management
#   - Supabase CLI pre-installed for migrations, functions, and testing
#   - psql CLI with convenience aliases
#   - Docker-in-Docker for Supabase's container orchestration
#   - Code-server web IDE
#   - SSH server access
#   - External preview via Traefik
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

data "coder_parameter" "preview_port" {
  name         = "preview_port"
  display_name = "App Preview Port"
  description  = "Port for your application preview"
  type         = "number"
  default      = "8080"
  mutable      = true
  order        = 100
}

data "coder_parameter" "external_preview" {
  name         = "external_preview"
  display_name = "External Preview"
  description  = "Enable external preview for your app via Traefik"
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

  preview_port             = data.coder_parameter.preview_port.value
  external_preview_enabled = data.coder_parameter.external_preview.value
  workspace_password       = data.coder_parameter.workspace_password.value
  ssh_enabled              = data.coder_parameter.enable_ssh.value
  ssh_password             = local.workspace_password != "" ? local.workspace_password : random_password.ssh_fallback.result
  ssh_port                 = try(module.ssh_server[0].ssh_port, 0)
  git_cli                  = data.coder_parameter.git_cli.value

  # Supabase default ports (inside the workspace container)
  supabase_studio_port = 54323
  supabase_api_port    = 54321
  supabase_db_port     = 54322
}

# =============================================================================
# PASSWORDS
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

resource "docker_volume" "docker_data" {
  name = "coder-${local.owner_name}-${local.workspace_name}-docker"
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
    echo "[STARTUP] Supabase workspace initialization..."
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

    # Ensure docker group exists and coder is a member
    sudo groupadd -f docker 2>/dev/null || true
    sudo usermod -aG docker coder 2>/dev/null || true

    # Start Docker daemon
    if ! sudo pgrep -x dockerd >/dev/null 2>&1; then
      echo "[STARTUP] Starting Docker daemon..."
      sudo sh -c 'dockerd > /tmp/dockerd.log 2>&1 &'
      WAITED=0
      while ! sudo docker info >/dev/null 2>&1; do
        sleep 1
        WAITED=$((WAITED + 1))
        if [ $WAITED -ge 60 ]; then
          echo "[STARTUP] WARNING: Docker daemon not ready after 60s"
          tail -20 /tmp/dockerd.log 2>/dev/null || true
          break
        fi
      done
      if sudo docker info >/dev/null 2>&1; then
        sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        echo "[STARTUP] Docker daemon ready"
      fi
    fi

    # ── Install PostgreSQL client ──
    if ! command -v psql >/dev/null 2>&1; then
      echo "[STARTUP] Installing PostgreSQL client..."
      (
        flock -w 300 9 || true
        sudo apt-get update -qq >/dev/null 2>&1
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[STARTUP] psql installed"
    fi

    # ── Install Supabase CLI ──
    if ! command -v supabase >/dev/null 2>&1; then
      echo "[STARTUP] Installing Supabase CLI..."
      ARCH=$(dpkg --print-architecture)
      if [ "$ARCH" = "amd64" ]; then
        SB_ARCH="linux_amd64"
      else
        SB_ARCH="linux_arm64"
      fi
      curl -fsSL "https://github.com/supabase/cli/releases/latest/download/supabase_$${SB_ARCH}.tar.gz" -o /tmp/supabase.tar.gz
      sudo tar -xzf /tmp/supabase.tar.gz -C /usr/local/bin supabase
      rm -f /tmp/supabase.tar.gz
      echo "[STARTUP] Supabase CLI installed: $(supabase --version 2>/dev/null || echo 'unknown')"
    fi

    echo "[STARTUP] User: $(whoami)"
    echo "[STARTUP] Docker: $(docker --version 2>/dev/null || echo 'not available')"
    echo "[STARTUP] Supabase CLI: $(supabase --version 2>/dev/null || echo 'not available')"
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
    display_name = "Supabase"
    key          = "supabase"
    script       = "if supabase status --workdir ~/workspace 2>/dev/null | grep -q 'Studio URL'; then echo 'Running'; else echo 'Stopped'; fi"
    interval     = 15
    timeout      = 5
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
# TRAEFIK ROUTING (App Preview)
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
# GIT PLATFORM CLI
# =============================================================================

module "git_platform_cli" {
  count  = local.git_cli != "none" ? 1 : 0
  source = "./modules/feature/git-platform-cli"

  agent_id    = coder_agent.main.id
  git_cli     = local.git_cli
  gitlab_host = ""
}

# =============================================================================
# SUPABASE INIT & START
# =============================================================================

resource "coder_script" "supabase_start" {
  agent_id           = coder_agent.main.id
  display_name       = "Supabase Start"
  icon               = "/icon/database.svg"
  run_on_start       = true
  start_blocks_login = true

  script = <<-SCRIPT
    #!/bin/bash
    set -e

    WORKSPACE_DIR="${local.workspace_folder}"
    cd "$WORKSPACE_DIR"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SUPABASE] Starting Supabase local development stack..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for Docker daemon
    echo "[SUPABASE] Waiting for Docker daemon..."
    MAX_WAIT=90
    WAITED=0
    while ! docker info >/dev/null 2>&1; do
      sleep 2
      WAITED=$((WAITED + 2))
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[SUPABASE] ERROR: Docker daemon not available after $${MAX_WAIT}s"
        exit 1
      fi
    done
    echo "[SUPABASE] Docker ready ($${WAITED}s)"

    # Wait for Supabase CLI
    MAX_WAIT=120
    WAITED=0
    while ! command -v supabase >/dev/null 2>&1; do
      sleep 2
      WAITED=$((WAITED + 2))
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[SUPABASE] ERROR: Supabase CLI not installed after $${MAX_WAIT}s"
        exit 1
      fi
    done
    echo "[SUPABASE] CLI ready: $(supabase --version)"

    # Initialize Supabase project if needed
    if [ ! -f "$WORKSPACE_DIR/supabase/config.toml" ]; then
      echo "[SUPABASE] Initializing new Supabase project..."
      supabase init --workdir "$WORKSPACE_DIR"
      echo "[SUPABASE] Project initialized"
    else
      echo "[SUPABASE] Project already initialized"
    fi

    # Start Supabase (pulls all required images automatically)
    echo "[SUPABASE] Starting services (this may take a few minutes on first run)..."
    supabase start --workdir "$WORKSPACE_DIR" 2>&1 | tee /tmp/supabase-start.log

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SUPABASE] SERVICES READY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    supabase status --workdir "$WORKSPACE_DIR" 2>/dev/null || true
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SUPABASE] ACCESS INSTRUCTIONS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Studio is available via the Supabase Studio button above."
    echo ""
    echo "  For full Studio interactivity, use port forwarding:"
    echo "    coder port-forward $(hostname) --tcp 54323:54323,54321:54321"
    echo "    Then open: http://localhost:54323"
    echo ""
    echo "  From inside this workspace (terminal/code):" 
    echo "    Studio:  http://localhost:54323"
    echo "    API:     http://localhost:54321"
    echo "    DB:      postgresql://postgres:postgres@localhost:54322/postgres"
    echo ""
    echo "  Supabase CLI commands:"
    echo "    supabase status          # Show service URLs & keys"
    echo "    supabase migration new   # Create a migration"
    echo "    supabase db reset        # Reset & re-run migrations"
    echo "    supabase gen types typescript --local  # Generate types"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  SCRIPT
}

# =============================================================================
# SUPABASE STUDIO (path-based proxy)
# =============================================================================
# Studio is a Next.js SPA that redirects / → /project/default.
# We point directly at /project/default to avoid the redirect breaking
# Coder's path-based proxy. Studio's JS API calls go to localhost:54321
# which works through the agent proxy.
#
# For full interactivity from your local machine, use port forwarding:
#   coder port-forward <workspace> --tcp 54323:54323,54321:54321
#   Then open: http://localhost:54323
# =============================================================================

resource "coder_app" "supabase_studio" {
  agent_id     = coder_agent.main.id
  slug         = "supabase-studio"
  display_name = "Supabase Studio"
  icon         = "/icon/database.svg"
  url          = "http://localhost:${local.supabase_studio_port}/project/default"
  subdomain    = false
  share        = "owner"
  order        = 10
}

# =============================================================================
# APP PREVIEW (user's application)
# =============================================================================
# This is for the user's own application, not Supabase services.
# No healthcheck — nothing runs on this port until the user starts their app.
# =============================================================================

resource "coder_app" "local_preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "App Preview"
  icon         = "/icon/widgets.svg"
  url          = "http://localhost:${local.preview_port}"
  subdomain    = false
  share        = "owner"
  order        = 12
}

# =============================================================================
# WORKSPACE CONTAINER
# =============================================================================

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  name       = local.container_name
  image      = docker_image.workspace.image_id
  hostname   = local.workspace_name
  privileged = true  # Required for Docker-in-Docker (supabase start uses Docker)

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

  # Docker data (persists pulled Supabase images across restarts)
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
  memory     = 4096  # 4GB — Supabase stack needs headroom

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
