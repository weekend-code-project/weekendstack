# =============================================================================
# MODULE: Kottster Admin Panel
# =============================================================================
# Provides Kottster (https://kottster.app) as a database admin panel.
#
# Features:
#   - Auto-installs Node.js 20+ and Kottster from template
#   - Auto-configures data source connection for the chosen database
#   - Traefik routing for external access via subdomain
#   - Supports: PostgreSQL, MySQL, MariaDB, SQLite
#
# The module creates:
#   - A coder_script to install and start Kottster
#   - A coder_app link for the admin panel
#   - Traefik labels are NOT managed here — they must be added
#     to the workspace container in the calling template
#
# Kottster uses Knex.js under the hood. Database type maps to Knex clients:
#   postgresql → pg, mysql → mysql, mariadb → mysql2, sqlite → sqlite3
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

variable "db_type" {
  description = "Database type: postgresql, mysql, mariadb, or sqlite"
  type        = string
  validation {
    condition     = contains(["postgresql", "mysql", "mariadb", "sqlite"], var.db_type)
    error_message = "db_type must be one of: postgresql, mysql, mariadb, sqlite"
  }
}

variable "db_host" {
  description = "Database host (ignored for sqlite)"
  type        = string
  default     = "localhost"
}

variable "db_port" {
  description = "Database port (ignored for sqlite)"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name (for sqlite, this is the file path)"
  type        = string
}

variable "db_user" {
  description = "Database username (ignored for sqlite)"
  type        = string
  default     = ""
}

variable "db_password" {
  description = "Database password (ignored for sqlite)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "admin_url" {
  description = "External URL for the admin panel (e.g., https://myworkspace-admin.example.com)"
  type        = string
}

variable "port" {
  description = "Port Kottster listens on inside the container"
  type        = number
  default     = 5480
}

# =============================================================================
# Locals
# =============================================================================

locals {
  kottster_dir = "/home/coder/kottster-admin"
  port         = var.port

  # Map our friendly db_type to Knex client names
  knex_client = {
    postgresql = "pg"
    mysql      = "mysql"
    mariadb    = "mysql2"
    sqlite     = "sqlite3"
  }[var.db_type]

  # SQLite uses filename, others use host/port/user/pass
  is_sqlite = var.db_type == "sqlite"
}

# =============================================================================
# Kottster Install & Start Script
# =============================================================================

resource "coder_script" "kottster" {
  agent_id           = var.agent_id
  display_name       = "Kottster Admin"
  icon               = "/icon/database.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-SCRIPT
    #!/bin/bash
    set -e

    KOTTSTER_DIR="${local.kottster_dir}"
    PORT="${local.port}"
    LOG_FILE="/tmp/kottster.log"
    PID_FILE="/tmp/kottster.pid"

    echo "[KOTTSTER] Setting up admin panel..."

    # ── Install Node.js 20+ if needed ──
    if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]; then
      echo "[KOTTSTER] Installing Node.js 20..."
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
      (
        flock -w 300 9 || true
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[KOTTSTER] Node.js installed: $(node -v)"
    fi

    # ── Clone and install Kottster if first time ──
    if [ ! -d "$KOTTSTER_DIR/node_modules" ]; then
      echo "[KOTTSTER] Creating Kottster admin project..."
      rm -rf "$KOTTSTER_DIR"
      git clone --depth 1 https://github.com/kottster/kottster-template-js "$KOTTSTER_DIR" 2>&1 | tail -3
      cd "$KOTTSTER_DIR"

      # Allow all hosts through Vite (required for external access via Traefik/Cloudflare)
      sed -i 's/server: {/server: {\n    allowedHosts: true,/' vite.config.js

      npm install 2>&1 | tail -5
      touch "$KOTTSTER_DIR/.install_complete"
      echo "[KOTTSTER] Project created"
    else
      touch "$KOTTSTER_DIR/.install_complete"
    fi

    # ── Auto-configure data source ──
    DS_DIR="$KOTTSTER_DIR/app/_server/data-sources/main"
    if [ ! -f "$DS_DIR/dataSource.json" ]; then
      echo "[KOTTSTER] Configuring ${var.db_type} data source..."
      mkdir -p "$DS_DIR"

      %{if local.is_sqlite}
      # SQLite data source
      cat > "$DS_DIR/dataSource.json" << 'DSEOF'
{
  "type": "${local.knex_client}",
  "connection": {
    "filename": "${var.db_name}"
  },
  "tablesConfig": {}
}
DSEOF

      cat > "$DS_DIR/index.js" << 'IDXEOF'
const knex = require('knex');

const dataSource = knex({
  client: '${local.knex_client}',
  connection: {
    filename: '${var.db_name}'
  },
  useNullAsDefault: true
});

module.exports = { dataSource };
IDXEOF
      %{else}
      # Server-based database data source
      cat > "$DS_DIR/dataSource.json" << 'DSEOF'
{
  "type": "${local.knex_client}",
  "connection": {
    "host": "${var.db_host}",
    "port": ${var.db_port},
    "user": "${var.db_user}",
    "password": "${var.db_password}",
    "database": "${var.db_name}"
  },
  "tablesConfig": {}
}
DSEOF

      cat > "$DS_DIR/index.js" << 'IDXEOF'
const knex = require('knex');

const dataSource = knex({
  client: '${local.knex_client}',
  connection: {
    host: '${var.db_host}',
    port: ${var.db_port},
    user: '${var.db_user}',
    password: '${var.db_password}',
    database: '${var.db_name}'
  }
});

module.exports = { dataSource };
IDXEOF
      %{endif}

      # Install the appropriate Knex driver
      cd "$KOTTSTER_DIR"
      %{if local.knex_client == "pg"}
      npm install pg 2>&1 | tail -3
      %{endif}
      %{if local.knex_client == "mysql"}
      npm install mysql 2>&1 | tail -3
      %{endif}
      %{if local.knex_client == "mysql2"}
      npm install mysql2 2>&1 | tail -3
      %{endif}
      %{if local.knex_client == "sqlite3"}
      npm install better-sqlite3 2>&1 | tail -3
      %{endif}

      echo "[KOTTSTER] Data source configured"
    fi

    # ── Wait for install to complete ──
    INSTALL_MARKER="$KOTTSTER_DIR/.install_complete"
    WAITED=0
    while [ ! -f "$INSTALL_MARKER" ] && [ $WAITED -lt 300 ]; do
      sleep 3
      WAITED=$((WAITED + 3))
    done
    sleep 5

    # ── Kill previous instance ──
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE")
      kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi

    cd "$KOTTSTER_DIR"
    export PATH="$KOTTSTER_DIR/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    # ── Start Kottster dev server ──
    nohup node "$KOTTSTER_DIR/node_modules/@kottster/cli/dist/index.js" dev > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 5

    if kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
      echo "[KOTTSTER] Running on port $PORT (PID: $(cat $PID_FILE))"
      echo "[KOTTSTER] Admin URL: ${var.admin_url}"
    else
      echo "[KOTTSTER] Failed to start. Check $LOG_FILE"
      cat "$LOG_FILE" 2>/dev/null | tail -10
    fi
  SCRIPT
}

# =============================================================================
# Preview Link
# =============================================================================

resource "coder_app" "kottster" {
  agent_id     = var.agent_id
  slug         = "kottster"
  display_name = "Database Admin"
  icon         = "/icon/database.svg"
  url          = var.admin_url
  external     = true
  order        = 10
}

# =============================================================================
# Outputs
# =============================================================================

output "port" {
  description = "Port Kottster is running on"
  value       = local.port
}

output "url" {
  description = "External URL for the admin panel"
  value       = var.admin_url
}

output "install_dir" {
  description = "Directory where Kottster is installed"
  value       = local.kottster_dir
}
