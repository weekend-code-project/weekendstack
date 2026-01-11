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
#   - SSH access (add ssh module)
#   - Git integration (add git module)  
#   - Traefik routing (add traefik module)
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
  
  # Startup script - basic environment setup only
  # The startup command runs via coder_script with high order to ensure it's LAST
  startup_script = <<-SCRIPT
    #!/bin/bash
    set -e
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP] 🚀 Workspace initialization starting..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Ensure workspace folder exists
    mkdir -p "${local.workspace_folder}"
    
    echo "[STARTUP] User: $(whoami)"
    echo "[STARTUP] Home: $HOME"
    echo "[STARTUP] Workspace: ${local.workspace_folder}"
    echo "[STARTUP] ✅ Environment ready!"
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
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP-CMD] 🚀 Startup Command Script"
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
        echo "[STARTUP-CMD] ✅ Code-server is running!"
        break
      fi
      # Also check log file for completion message
      if [ -f /tmp/code-server.log ] && grep -q "HTTP server listening" /tmp/code-server.log 2>/dev/null; then
        echo "[STARTUP-CMD] ✅ Code-server is ready!"
        break
      fi
      sleep 2
      WAITED=$((WAITED + 2))
    done
    
    if [ $WAITED -ge $MAX_WAIT ]; then
      echo "[STARTUP-CMD] ⚠️  Timeout waiting for code-server ($MAX_WAIT s), proceeding anyway"
    fi
    
    echo "[STARTUP-CMD] Command: $STARTUP_CMD"
    echo "[STARTUP-CMD] Directory: $WORKSPACE_DIR"
    echo "[STARTUP-CMD] Logs: $LOG_FILE"
    
    # Change to workspace directory
    cd "$WORKSPACE_DIR"
    
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
      echo "[STARTUP-CMD] ✅ Server started successfully (PID: $SERVER_PID)"
    else
      echo "[STARTUP-CMD] ⚠️  Server may have failed. Check $LOG_FILE"
      tail -5 "$LOG_FILE" 2>/dev/null || true
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP-CMD] ✅ Done!"
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
  
  # Home directory persistence
  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
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
