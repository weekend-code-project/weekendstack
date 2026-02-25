# =============================================================================
# BASE TEMPLATE v2
# =============================================================================
# A minimal Coder workspace template with code-server IDE.
# This is the foundation that all other templates build upon.
#
# Features:
#   - Ubuntu container with Coder agent
#   - Home directory persistence via Docker volume
#   - Code-server web IDE (opens to /home/coder/workspace)
#   - Basic resource monitoring
#
# This template does NOT include:
#   - Git integration (add git module)
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

# GitHub External Auth (optional - requires Coder server configuration)
# When enabled, provides OAuth token for private repo access via HTTPS.
# Users see a "Connect to GitHub" button on first workspace if not yet authorized.
data "coder_external_auth" "github" {
  count    = var.github_external_auth ? 1 : 0
  id       = "github"
  optional = true
}

# =============================================================================
# PARAMETERS (User-configurable in Coder UI)
# =============================================================================

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run after workspace is ready. Runs in /home/coder/workspace. Leave empty to disable."
  type         = "string"
  default      = "python3 -m http.server 8080"
  mutable      = true
  order        = 100
}

data "coder_parameter" "preview_port" {
  name         = "preview_port"
  display_name = "Preview Port"
  description  = "Port for the local preview server (used by startup command)"
  type         = "number"
  default      = "8080"
  mutable      = true
  order        = 101
}

data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Auto-Generate HTML"
  description  = "Generate a default index.html if none exists in workspace. Regenerates on each start if enabled."
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 102
}

data "coder_parameter" "external_preview" {
  name         = "external_preview"
  display_name = "External Preview"
  description  = "Enable external preview via Traefik tunnel (requires password)."
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 200
}

data "coder_parameter" "workspace_password" {
  name         = "workspace_password"
  display_name = "Workspace Password"
  description  = "Password for SSH access and external preview. If empty, a random password is generated for SSH."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 201
}

data "coder_parameter" "enable_ssh" {
  name         = "enable_ssh"
  display_name = "Enable SSH"
  description  = "Start SSH server and generate SSH keys for Git. Provides remote terminal access and auto-generates an ed25519 key pair."
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 300
}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository URL"
  description  = "Git repository to clone into workspace (SSH or HTTPS). Leave empty to skip."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 400
}

# =============================================================================
# LOCALS
# =============================================================================

locals {
  # Workspace naming
  workspace_name = lower(data.coder_workspace.me.name)
  owner_name     = data.coder_workspace_owner.me.name
  container_name = "coder-${local.owner_name}-${local.workspace_name}"
  
  # Paths
  workspace_folder = "/home/coder/workspace"
  
  # Base image
  docker_image = "codercom/enterprise-base:ubuntu"
  
  # ==========================================================================
  # DEFAULT STARTUP COMMAND (Template-level default)
  # ==========================================================================
  # This sets the DEFAULT value for the startup_command parameter.
  # Users can override via the Coder UI parameter.
  #
  # To change the default for a specific template, override this local:
  #   node:      "npm run dev -- --host 0.0.0.0 --port 8080"
  #   vite:      "npm run dev -- --host 0.0.0.0 --port 8080"
  #   wordpress: "apache2-foreground"
  # ==========================================================================
  default_startup_command = "python3 -m http.server 8080"
  
  # Actual command to run (from parameter, falls back to default)
  startup_command = data.coder_parameter.startup_command.value
  
  # Preview port (from parameter)
  preview_port = data.coder_parameter.preview_port.value
  
  # Auto-generate HTML toggle
  auto_generate_html = data.coder_parameter.auto_generate_html.value
  
  # External preview settings
  external_preview_enabled = data.coder_parameter.external_preview.value
  workspace_password       = data.coder_parameter.workspace_password.value
  
  # SSH settings
  ssh_enabled  = data.coder_parameter.enable_ssh.value
  ssh_password = local.workspace_password != "" ? local.workspace_password : random_password.ssh_fallback.result
  ssh_port     = try(module.ssh_server[0].ssh_port, 0)
}

# =============================================================================
# AUTO-GENERATED SSH PASSWORD (fallback when user doesn't set one)
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
  
  lifecycle {
    # Keep volume when workspace is destroyed (data persistence)
    prevent_destroy = false
  }
}

# =============================================================================
# CODER AGENT
# =============================================================================

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = local.workspace_folder
  
  # Startup script - environment initialization
  # Handles first-time home directory setup + workspace folder creation
  startup_script = <<-SCRIPT
    #!/bin/bash
    set -e
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP] Workspace initialization starting..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # First-time home directory initialization
    if [ ! -f "$HOME/.init_done" ]; then
      echo "[STARTUP] First startup detected, initializing home..."
      cp -rT /etc/skel "$HOME" 2>/dev/null || true
      
      # Standard directories
      mkdir -p "$HOME/workspace"
      mkdir -p "$HOME/.config"
      mkdir -p "$HOME/.local/bin"
      chmod 755 "$HOME/workspace"
      
      # Auto-cd to workspace in interactive shells
      if ! grep -q "cd ~/workspace" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# Auto-navigate to workspace directory" >> "$HOME/.bashrc"
        echo "cd ~/workspace 2>/dev/null || true" >> "$HOME/.bashrc"
      fi
      
      touch "$HOME/.init_done"
      echo "[STARTUP] Home directory initialized"
    else
      echo "[STARTUP] Home directory already initialized"
    fi
    
    # Ensure workspace folder exists (always)
    mkdir -p "${local.workspace_folder}"
    
    echo "[STARTUP] User: $(whoami)"
    echo "[STARTUP] Home: $HOME"
    echo "[STARTUP] Workspace: ${local.workspace_folder}"
    echo "[STARTUP] Environment ready"
  SCRIPT
  
  # Disable VS Code Desktop button (web-based code-server only)
  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }
  
  # Git identity from Coder workspace owner
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }
  
  # Basic resource monitoring
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
  
  metadata {
    display_name = "Git Branch"
    key          = "git_branch"
    script       = "cd /home/coder/workspace 2>/dev/null && git branch --show-current 2>/dev/null | grep . || echo '-'"
    interval     = 10
    timeout      = 1
  }
}

# =============================================================================
# CODE SERVER (Web IDE)
# =============================================================================

module "code_server" {
  source = "./modules/feature/code-server"
  
  agent_id = coder_agent.main.id
  folder   = local.workspace_folder
  order    = 1
}

# =============================================================================
# TRAEFIK ROUTING (External Preview)
# =============================================================================
# When enabled, provides external access via Traefik reverse proxy.
# Creates subdomain route: {workspace}.{base_domain}
# Requires password for basic auth protection.
# =============================================================================

module "traefik_routing" {
  source = "./modules/feature/traefik-routing"
  
  agent_id                 = coder_agent.main.id
  workspace_name           = local.workspace_name
  workspace_owner          = local.owner_name
  workspace_owner_id       = data.coder_workspace_owner.me.id
  workspace_id             = data.coder_workspace.me.id
  base_domain              = var.base_domain
  preview_port             = local.preview_port
  external_preview_enabled = local.external_preview_enabled
  workspace_password       = local.workspace_password
  # Note: traefik_auth_dir not passed - module uses fixed /traefik-auth mount point
}

# =============================================================================
# SSH SERVER (Remote access + key generation)
# =============================================================================
# When enabled, provides SSH access and generates ed25519 key pair for Git.
# SSH port is deterministic per workspace (same across restarts).
# Public key is displayed in the build log for easy copying.
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
# Sets git config (user.name, user.email, safe.directory) and optionally
# clones a repository into the workspace on first startup.
# Git SSH auth is handled natively by Coder via $GIT_SSH_COMMAND.
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
# LOCAL PREVIEW (Coder's built-in proxy)
# =============================================================================
# This uses Coder's built-in proxy to access the dev server.
# Works immediately via Coder's authenticated proxy URL.
# For external access via domain name, enable External Preview above.
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
# STARTUP COMMAND (Runs after other scripts)
# =============================================================================
# Note: coder_script resources run in parallel. We use start_blocks_login=false
# and add a delay to allow code-server to install first.
# The startup command runs in background so it doesn't block the workspace.
# =============================================================================

resource "coder_script" "startup_command" {
  agent_id           = coder_agent.main.id
  display_name       = "Startup Command"
  icon               = "/icon/play.svg"
  run_on_start       = true
  start_blocks_login = false  # Don't block login, run in background
  
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
    echo "[STARTUP-CMD] Startup Command Script"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -z "$STARTUP_CMD" ]; then
      echo "[STARTUP-CMD] No command configured (skipping)"
      exit 0
    fi
    
    # Wait for code-server to be ready
    # Check for the process running OR the install complete message in logs
    echo "[STARTUP-CMD] Waiting for code-server..."
    MAX_WAIT=60
    WAITED=0
    while [ $WAITED -lt $MAX_WAIT ]; do
      # Check if code-server process is running
      if pgrep -f "code-server" > /dev/null 2>&1; then
        echo "[STARTUP-CMD] Code-server is running"
        break
      fi
      # Also check log file for completion message
      if [ -f /tmp/code-server.log ] && grep -q "HTTP server listening" /tmp/code-server.log 2>/dev/null; then
        echo "[STARTUP-CMD] Code-server is ready"
        break
      fi
      sleep 2
      WAITED=$((WAITED + 2))
    done
    
    if [ $WAITED -ge $MAX_WAIT ]; then
      echo "[STARTUP-CMD] Timeout waiting for code-server ($MAX_WAIT s), proceeding anyway"
    fi
    
    # Change to workspace directory first (create if git clone hasn't run yet)
    mkdir -p "$WORKSPACE_DIR"
    cd "$WORKSPACE_DIR"
    
    # Auto-generate HTML if enabled
    if [ "$AUTO_HTML" = "true" ]; then
      echo "[STARTUP-CMD] Auto-generate HTML is enabled"
      if [ ! -f "$WORKSPACE_DIR/index.html" ]; then
        echo "[STARTUP-CMD] Generating default index.html..."
        cat > "$WORKSPACE_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Workspace Preview</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            background: white;
            padding: 40px 50px;
            border-radius: 16px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
            width: 100%;
        }
        h1 {
            color: #333;
            font-size: 2em;
            margin-bottom: 10px;
        }
        .status {
            background: linear-gradient(135deg, #84fab0 0%, #8fd3f4 100%);
            padding: 20px;
            border-radius: 8px;
            margin: 25px 0;
            font-size: 1.2em;
            font-weight: 600;
            color: #2d5a3d;
        }
        .info {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
            text-align: left;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #eee;
        }
        .info-row:last-child { border-bottom: none; }
        .info-label { color: #666; }
        .info-value { font-weight: 600; color: #333; }
        code {
            background: #e9ecef;
            padding: 3px 8px;
            border-radius: 4px;
            font-family: 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }
        .footer {
            margin-top: 30px;
            color: #999;
            font-size: 0.85em;
        }
        .tip {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 8px;
            margin-top: 20px;
            font-size: 0.9em;
            color: #856404;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Workspace Preview</h1>
        
        <div class="status">
            Server Running
        </div>
        
        <div class="info">
            <div class="info-row">
                <span class="info-label">Status</span>
                <span class="info-value">Active</span>
            </div>
            <div class="info-row">
                <span class="info-label">Server</span>
                <span class="info-value">Python HTTP Server</span>
            </div>
            <div class="info-row">
                <span class="info-label">Directory</span>
                <span class="info-value"><code>/home/coder/workspace</code></span>
            </div>
        </div>
        
        <div class="tip">
            <strong>Tip:</strong> Replace this file with your own <code>index.html</code> or disable auto-generation in workspace settings.
        </div>
        
        <div class="footer">
            Auto-generated by Coder
        </div>
    </div>
</body>
</html>
HTMLEOF
        echo "[STARTUP-CMD] Created index.html"
      else
        echo "[STARTUP-CMD] index.html already exists (keeping existing)"
      fi
    else
      echo "[STARTUP-CMD] Auto-generate HTML disabled"
    fi
    
    echo "[STARTUP-CMD] Command: $STARTUP_CMD"
    echo "[STARTUP-CMD] Directory: $WORKSPACE_DIR"
    echo "[STARTUP-CMD] Port: $PREVIEW_PORT"
    echo "[STARTUP-CMD] Logs: $LOG_FILE"
    
    # Kill any existing process from previous run
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE")
      if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[STARTUP-CMD] Stopping previous server (PID: $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
      fi
    fi
    
    # Run the startup command in background
    echo "[STARTUP-CMD] Starting server..."
    nohup bash -c "$STARTUP_CMD" > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo $SERVER_PID > "$PID_FILE"
    
    # Give it a moment to start
    sleep 2
    
    # Check if it's still running
    if kill -0 $SERVER_PID 2>/dev/null; then
      echo "[STARTUP-CMD] Server started successfully (PID: $SERVER_PID)"
    else
      echo "[STARTUP-CMD] Server may have failed. Check $LOG_FILE"
      tail -5 "$LOG_FILE" 2>/dev/null || true
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP-CMD] Done"
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
  
  # Run the Coder agent init script
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  # Connect to coder network for internal communication
  networks_advanced {
    name = "coder-network"
  }
  
  # Traefik labels for external routing (when enabled)
  dynamic "labels" {
    for_each = module.traefik_routing.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  
  # SSH port mapping (when SSH is enabled)
  dynamic "ports" {
    for_each = try([module.ssh_server[0].ssh_port], [])
    content {
      internal = try(module.ssh_server[0].internal_port, 2222)
      external = ports.value
    }
  }
  
  # Hide from Glance dashboard
  labels {
    label = "glance.hide"
    value = "true"
  }
  
  # Home directory persistence
  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
  }
  
  # Traefik auth directory (shared with Traefik for basic auth)
  # Host path (traefik_auth_dir) maps to /traefik-auth inside container
  # Traefik also mounts the same host path to /traefik-auth
  mounts {
    type      = "bind"
    source    = var.traefik_auth_dir
    target    = "/traefik-auth"
    read_only = false
  }

  # Basic environment
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]
  
  # Keep container running
  stdin_open = true
  tty        = true
  
  # Resource limits (reasonable defaults)
  memory = 2048  # 2GB
  
  # Lifecycle
  lifecycle {
    ignore_changes = [
      # Ignore changes to image to prevent recreation on pull
      image,
    ]
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
