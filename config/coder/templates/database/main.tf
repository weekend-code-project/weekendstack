# =============================================================================
# DATABASE TEMPLATE
# =============================================================================
# A unified database development workspace supporting multiple database engines
# with Kottster as the admin panel.
#
# Supported databases:
#   - PostgreSQL 16 (sidecar container)
#   - MySQL 8.0 (sidecar container)
#   - MariaDB 11 (sidecar container)
#   - SQLite (file-based, no sidecar)
#
# Features:
#   - Database engine selection via dropdown
#   - Kottster admin panel auto-configured for chosen database
#   - CLI tools for the selected database
#   - Sample data option
#   - SSH server access
#   - External Traefik routing for admin panel
#
# All functionality is inlined (no external modules) for maximum
# compatibility with Coder's template parameter parser.
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

data "coder_parameter" "db_engine" {
  name         = "db_engine"
  display_name = "Database Engine"
  description  = "Choose which database to provision"
  type         = "string"
  default      = "postgresql"
  mutable      = false
  order        = 1

  option {
    name        = "PostgreSQL"
    value       = "postgresql"
    description = "PostgreSQL 16 — powerful, open source object-relational database"
    icon        = "/icon/database.svg"
  }
  option {
    name        = "MySQL"
    value       = "mysql"
    description = "MySQL 8 — the world's most popular open source database"
    icon        = "/icon/database.svg"
  }
  option {
    name        = "MariaDB"
    value       = "mariadb"
    description = "MariaDB 11 — community-developed fork of MySQL"
    icon        = "/icon/database.svg"
  }
  option {
    name        = "SQLite"
    value       = "sqlite"
    description = "SQLite — lightweight, file-based, zero-config database"
    icon        = "/icon/database.svg"
  }
}

data "coder_parameter" "db_name" {
  name         = "db_name"
  display_name = "Database Name"
  description  = "Name of the database (or filename for SQLite, e.g. dev.db)"
  type         = "string"
  default      = "devdb"
  mutable      = false
  order        = 10
}

data "coder_parameter" "create_sample_data" {
  name         = "create_sample_data"
  display_name = "Create Sample Data"
  description  = "Populate database with sample tables and data on first start"
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 12
}

data "coder_parameter" "workspace_password" {
  name         = "workspace_password"
  display_name = "Workspace Password"
  description  = "Password for SSH and database access. Empty = auto-generated."
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

  # Database configuration
  db_engine          = data.coder_parameter.db_engine.value
  db_name            = data.coder_parameter.db_name.value
  create_sample_data = data.coder_parameter.create_sample_data.value

  # Booleans for each engine
  is_sqlite     = local.db_engine == "sqlite"
  is_postgresql = local.db_engine == "postgresql"
  is_mysql      = local.db_engine == "mysql"
  is_mariadb    = local.db_engine == "mariadb"
  needs_sidecar = !local.is_sqlite

  # Database sidecar container naming
  db_container = "${local.db_engine}-${local.workspace_name}"

  # Default ports
  db_port = local.is_postgresql ? 5432 : (local.is_mysql || local.is_mariadb ? 3306 : 0)

  # Database credentials
  workspace_password = data.coder_parameter.workspace_password.value
  db_password        = local.workspace_password != "" ? local.workspace_password : random_password.db_password.result
  db_user            = local.is_postgresql ? "postgres" : "root"
  ssh_enabled        = data.coder_parameter.enable_ssh.value
  ssh_password       = local.workspace_password != "" ? local.workspace_password : random_password.db_password.result

  # SSH
  ssh_port     = random_integer.ssh_port.result
  ssh_internal = 2222

  # SQLite specific
  sqlite_filename = local.is_sqlite ? local.db_name : ""
  sqlite_db_path  = local.is_sqlite ? "${local.workspace_folder}/${local.sqlite_filename}" : ""

  # Docker images for each engine (latest stable)
  db_image = {
    postgresql = "postgres:16"
    mysql      = "mysql:8.0"
    mariadb    = "mariadb:11"
    sqlite     = ""
  }[local.db_engine]

  # Knex client mapping for Kottster
  knex_client = {
    postgresql = "pg"
    mysql      = "mysql2"
    mariadb    = "mysql2"
    sqlite     = "better-sqlite3"
  }[local.db_engine]

  # Kottster data source type (used by kottster add-data-source CLI)
  kottster_ds_type = {
    postgresql = "postgres"
    mysql      = "mysql"
    mariadb    = "mariadb"
    sqlite     = "sqlite"
  }[local.db_engine]

  # Knex driver npm package
  knex_driver_pkg = {
    postgresql = "pg"
    mysql      = "mysql2"
    mariadb    = "mysql2"
    sqlite     = "better-sqlite3"
  }[local.db_engine]

  # Kottster admin panel
  kottster_port = 5480
  kottster_dir  = "/home/coder/kottster-admin"
  admin_router  = "${local.workspace_name}-admin"
  admin_url     = "https://${local.workspace_name}-admin.${var.base_domain}"

  # Connection strings for display
  connection_info = {
    postgresql = "postgresql://${local.db_user}:${local.db_password}@${local.db_container}:${local.db_port}/${local.db_name}"
    mysql      = "mysql://${local.db_user}:${local.db_password}@${local.db_container}:${local.db_port}/${local.db_name}"
    mariadb    = "mysql://${local.db_user}:${local.db_password}@${local.db_container}:${local.db_port}/${local.db_name}"
    sqlite     = local.sqlite_db_path
  }[local.db_engine]
}

# =============================================================================
# PASSWORDS & PORTS
# =============================================================================

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "random_integer" "ssh_port" {
  min = 23000
  max = 29999
  keepers = {
    workspace_id = data.coder_workspace.me.id
  }
}

# =============================================================================
# DOCKER IMAGES
# =============================================================================

data "docker_registry_image" "workspace" {
  name = local.docker_image
}

resource "docker_image" "workspace" {
  name          = data.docker_registry_image.workspace.name
  pull_triggers = [data.docker_registry_image.workspace.sha256_digest]
  keep_locally  = true
}

resource "docker_image" "database" {
  count        = local.needs_sidecar ? 1 : 0
  name         = local.db_image
  keep_locally = true
}

# =============================================================================
# PERSISTENT STORAGE
# =============================================================================

resource "docker_volume" "home" {
  name = "coder-${local.owner_name}-${local.workspace_name}-home"
}

resource "docker_volume" "db_data" {
  count = local.needs_sidecar ? 1 : 0
  name  = "coder-${local.owner_name}-${local.workspace_name}-dbdata"
}

# =============================================================================
# DATABASE SIDECAR CONTAINER (PostgreSQL / MySQL / MariaDB)
# =============================================================================

resource "docker_container" "database" {
  count    = local.needs_sidecar ? data.coder_workspace.me.start_count : 0
  image    = docker_image.database[0].image_id
  name     = local.db_container
  hostname = local.db_container

  env = local.is_postgresql ? [
    "POSTGRES_USER=${local.db_user}",
    "POSTGRES_PASSWORD=${local.db_password}",
    "POSTGRES_DB=${local.db_name}",
  ] : local.is_mysql ? [
    "MYSQL_ROOT_PASSWORD=${local.db_password}",
    "MYSQL_DATABASE=${local.db_name}",
  ] : local.is_mariadb ? [
    "MARIADB_ROOT_PASSWORD=${local.db_password}",
    "MARIADB_DATABASE=${local.db_name}",
  ] : []

  networks_advanced {
    name    = "coder-network"
    aliases = [local.db_container, local.db_engine]
  }

  volumes {
    volume_name    = docker_volume.db_data[0].name
    container_path = local.is_postgresql ? "/var/lib/postgresql/data" : "/var/lib/mysql"
  }

  healthcheck {
    test = local.is_postgresql ? [
      "CMD-SHELL", "pg_isready -U ${local.db_user}"
    ] : [
      "CMD-SHELL", "mysqladmin ping -h localhost -u${local.db_user} -p${local.db_password}"
    ]
    interval     = "5s"
    timeout      = "3s"
    retries      = 30
    start_period = "10s"
  }

  labels {
    label = "glance.hide"
    value = "true"
  }

  restart = "unless-stopped"
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
    echo "[STARTUP] Database workspace initialization (${local.db_engine})..."
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

    # ── Install CLI tools based on database engine ──
    %{if local.is_sqlite}
    if ! command -v sqlite3 >/dev/null 2>&1; then
      echo "[STARTUP] Installing SQLite3..."
      (
        flock -w 300 9 || true
        sudo apt-get update -qq >/dev/null 2>&1
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sqlite3 libsqlite3-dev >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[STARTUP] SQLite3 installed: $(sqlite3 --version)"
    fi
    %{endif}

    %{if local.is_postgresql}
    if ! command -v psql >/dev/null 2>&1; then
      echo "[STARTUP] Installing PostgreSQL client..."
      (
        flock -w 300 9 || true
        sudo apt-get update -qq >/dev/null 2>&1
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[STARTUP] psql installed: $(psql --version)"
    fi
    %{endif}

    %{if local.is_mysql || local.is_mariadb}
    if ! command -v mysql >/dev/null 2>&1; then
      echo "[STARTUP] Installing MySQL client..."
      (
        flock -w 300 9 || true
        sudo apt-get update -qq >/dev/null 2>&1
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-client >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[STARTUP] mysql installed: $(mysql --version)"
    fi
    %{endif}

    # ── Wait for database sidecar (non-SQLite) ──
    %{if local.needs_sidecar}
    echo "[STARTUP] Waiting for ${local.db_engine} (${local.db_container})..."
    MAX_WAIT=120
    WAITED=0
    while true; do
      %{if local.is_postgresql}
      if PGPASSWORD="${local.db_password}" psql -h "${local.db_container}" -U ${local.db_user} -d "${local.db_name}" -c "SELECT 1" >/dev/null 2>&1; then
        echo "[STARTUP] PostgreSQL is ready ($${WAITED}s)"
        break
      fi
      %{endif}
      %{if local.is_mysql || local.is_mariadb}
      if mysqladmin ping -h "${local.db_container}" -u${local.db_user} -p"${local.db_password}" --silent 2>/dev/null; then
        echo "[STARTUP] ${local.db_engine} is ready ($${WAITED}s)"
        break
      fi
      %{endif}
      sleep 2
      WAITED=$((WAITED + 2))
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[STARTUP] WARNING: Database not ready after $${MAX_WAIT}s"
        break
      fi
      [ $((WAITED % 10)) -eq 0 ] && [ $WAITED -gt 0 ] && echo "[STARTUP] Still waiting ($${WAITED}s)..."
    done
    %{endif}

    # ── Create SQLite database and sample data ──
    %{if local.is_sqlite}
    DB_PATH="${local.sqlite_db_path}"
    if [ ! -f "$DB_PATH" ]; then
      echo "[STARTUP] Creating database: $DB_PATH"
      sqlite3 "$DB_PATH" "SELECT 1;" >/dev/null 2>&1

      if [ "${local.create_sample_data}" = "true" ]; then
        echo "[STARTUP] Creating sample tables and data..."
        sqlite3 "$DB_PATH" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    published BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com'), ('bob', 'bob@example.com');
INSERT INTO posts (user_id, title, body, published) VALUES
    (1, 'Getting Started', 'Welcome to your SQLite workspace!', 1),
    (2, 'Draft Post', 'Work in progress...', 0);
SQLEOF
        echo "[STARTUP] Sample data created"
      fi
    fi

    if ! grep -q "alias dbopen" "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" << 'ALIASES'

# Database convenience aliases
alias dbopen='sqlite3 ${local.sqlite_db_path}'
alias dbtables='sqlite3 ${local.sqlite_db_path} ".tables"'
alias dbschema='sqlite3 ${local.sqlite_db_path} ".schema"'
ALIASES
    fi
    %{endif}

    # ── Create PostgreSQL sample data ──
    %{if local.is_postgresql}
    if [ "${local.create_sample_data}" = "true" ]; then
      TABLE_EXISTS=$(PGPASSWORD="${local.db_password}" psql -h "${local.db_container}" -U ${local.db_user} -d "${local.db_name}" -t -c "SELECT EXISTS(SELECT FROM information_schema.tables WHERE table_name='users')" 2>/dev/null | xargs)
      if [ "$TABLE_EXISTS" != "t" ]; then
        echo "[STARTUP] Creating sample tables and data..."
        PGPASSWORD="${local.db_password}" psql -h "${local.db_container}" -U ${local.db_user} -d "${local.db_name}" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    body TEXT,
    published BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com'), ('bob', 'bob@example.com');
INSERT INTO posts (user_id, title, body, published) VALUES
    (1, 'Getting Started', 'Welcome to your PostgreSQL workspace!', true),
    (2, 'Draft Post', 'Work in progress...', false);
SQLEOF
        echo "[STARTUP] Sample data created"
      fi
    fi

    echo "${local.db_container}:5432:*:${local.db_user}:${local.db_password}" > "$HOME/.pgpass"
    chmod 600 "$HOME/.pgpass"

    if ! grep -q "alias dbconnect" "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" << 'ALIASES'

# Database convenience aliases
alias dbconnect='psql -h ${local.db_container} -U ${local.db_user} -d ${local.db_name}'
alias dblist='psql -h ${local.db_container} -U ${local.db_user} -l'
ALIASES
    fi
    %{endif}

    # ── Create MySQL/MariaDB sample data ──
    %{if local.is_mysql || local.is_mariadb}
    if [ "${local.create_sample_data}" = "true" ]; then
      TABLE_EXISTS=$(mysql -h "${local.db_container}" -u${local.db_user} -p"${local.db_password}" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${local.db_name}' AND table_name='users'" -sN 2>/dev/null)
      if [ "$TABLE_EXISTS" = "0" ] || [ -z "$TABLE_EXISTS" ]; then
        echo "[STARTUP] Creating sample tables and data..."
        mysql -h "${local.db_container}" -u${local.db_user} -p"${local.db_password}" "${local.db_name}" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(100) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    published BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com'), ('bob', 'bob@example.com');
INSERT INTO posts (user_id, title, body, published) VALUES
    (1, 'Getting Started', 'Welcome to your database workspace!', true),
    (2, 'Draft Post', 'Work in progress...', false);
SQLEOF
        echo "[STARTUP] Sample data created"
      fi
    fi

    if ! grep -q "alias dbconnect" "$HOME/.bashrc" 2>/dev/null; then
      cat >> "$HOME/.bashrc" << 'ALIASES'

# Database convenience aliases
alias dbconnect='mysql -h ${local.db_container} -u${local.db_user} -p"${local.db_password}" ${local.db_name}'
alias dblist='mysql -h ${local.db_container} -u${local.db_user} -p"${local.db_password}" -e "SHOW DATABASES"'
ALIASES
    fi
    %{endif}

    # ── Install Node.js 20+ (for Kottster admin panel) ──
    if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]; then
      echo "[STARTUP] Installing Node.js 20..."
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
      # Force upgrade: remove system nodejs first if present (base image ships v18)
      dpkg -l nodejs 2>/dev/null | grep -q "^ii" && sudo apt-get remove -y nodejs libnode-dev 2>/dev/null || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs 2>/dev/null
      echo "[STARTUP] Node.js installed: $(node -v)"
    fi

    # ── Set up Kottster admin panel ──
    KOTTSTER_DIR="${local.kottster_dir}"
    if [ ! -d "$KOTTSTER_DIR/node_modules" ]; then
      echo "[STARTUP] Creating Kottster admin project..."
      rm -rf "$KOTTSTER_DIR"
      git clone --depth 1 https://github.com/kottster/kottster-template-js "$KOTTSTER_DIR" 2>&1 | tail -3
      cd "$KOTTSTER_DIR"

      # Allow all hosts through Vite (required for external access via Traefik/Cloudflare)
      sed -i 's/server: {/server: {\n    allowedHosts: true,/' vite.config.js

      npm install 2>&1 | tail -5

      # Install the Knex database driver
      cd "$KOTTSTER_DIR"
      npm install ${local.knex_driver_pkg} 2>&1 | tail -3

      # Auto-configure data source using Kottster CLI
      cd "$KOTTSTER_DIR"
      export PATH="$KOTTSTER_DIR/node_modules/.bin:$PATH"

      %{if local.is_sqlite}
      # SQLite: connection details with filename
      DS_DATA=$(echo -n '{"connectionDetails":{"connection":{"filename":"${local.sqlite_db_path}"},"useNullAsDefault":true}}' | base64 -w 0)
      %{else}
      # ${local.db_engine}: connection details with host/port/user/password/database
      DS_DATA=$(echo -n '{"connectionDetails":{"connection":{"host":"${local.db_container}","port":${local.db_port},"user":"${local.db_user}","password":"${local.db_password}","database":"${local.db_name}"}}}' | base64 -w 0)
      %{endif}

      echo "[STARTUP] Adding ${local.kottster_ds_type} data source via Kottster CLI..."
      npx kottster add-data-source ${local.kottster_ds_type} --skipInstall --name main --data "$DS_DATA" 2>&1 || {
        echo "[STARTUP] WARNING: kottster add-data-source failed, data source may need manual configuration"
      }

      # Signal that install is complete (used by kottster script)
      touch "$KOTTSTER_DIR/.install_complete"
      echo "[STARTUP] Kottster admin project created"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP] DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Engine:        ${local.db_engine}"
    %{if local.is_sqlite}
    echo "  Database:      ${local.sqlite_db_path}"
    echo "  SQLite:        $(sqlite3 --version 2>/dev/null | awk '{print $1}')"
    %{else}
    echo "  Host:          ${local.db_container}"
    echo "  Port:          ${local.db_port}"
    echo "  Database:      ${local.db_name}"
    echo "  User:          ${local.db_user}"
    echo "  Password:      ${local.db_password}"
    %{endif}
    echo "  Admin Panel:   ${local.admin_url}"
    echo "  Admin Login:   admin / ${local.db_password}"
    echo "  CLI:           dbconnect"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[STARTUP] Environment ready"
  SCRIPT

  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = false
    port_forwarding_helper = false
  }

  env = merge(
    {
      GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
      GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
      GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
      GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    },
    local.is_sqlite ? {
      SQLITE_DB = local.sqlite_db_path
    } : {},
    local.is_postgresql ? {
      PGHOST     = local.db_container
      PGUSER     = local.db_user
      PGDATABASE = local.db_name
      PGPASSWORD = local.db_password
    } : {},
    (local.is_mysql || local.is_mariadb) ? {
      MYSQL_HOST = local.db_container
      MYSQL_USER = local.db_user
      MYSQL_PWD  = local.db_password
    } : {}
  )

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
    display_name = "Database"
    key          = "dbstatus"
    script       = local.is_sqlite ? "if [ -f '${local.sqlite_db_path}' ]; then echo \"SQLite $(du -h '${local.sqlite_db_path}' | awk '{print $1}')\"; else echo 'No database'; fi" : local.is_postgresql ? "PGPASSWORD='${local.db_password}' psql -h ${local.db_container} -U ${local.db_user} -t -c \"SELECT pg_size_pretty(pg_database_size('${local.db_name}'))\" 2>/dev/null | xargs || echo 'Connecting...'" : "mysql -h ${local.db_container} -u${local.db_user} -p'${local.db_password}' -sN -e \"SELECT CONCAT(ROUND(SUM(data_length+index_length)/1024/1024,1),'MB') FROM information_schema.tables WHERE table_schema='${local.db_name}'\" 2>/dev/null || echo 'Connecting...'"
    interval     = 30
    timeout      = 3
  }

  metadata {
    display_name = "Admin Panel"
    key          = "kottster"
    script       = "pgrep -f kottster >/dev/null && echo 'Running :${local.kottster_port}' || echo 'Stopped'"
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
# SSH SERVER (inlined from ssh-server module)
# =============================================================================

resource "coder_script" "ssh_setup" {
  agent_id           = coder_agent.main.id
  display_name       = "SSH Server"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-EOT
    #!/bin/bash
    set -e

    SSH_ENABLED="${local.ssh_enabled}"
    if [ "$SSH_ENABLED" != "true" ]; then
      echo "[SSH] SSH server disabled by parameter"
      exit 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SSH] Setting up SSH server..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! command -v sshd >/dev/null 2>&1; then
      echo "[SSH] Installing OpenSSH server..."
      (
        flock -w 300 9 || true
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y -qq openssh-server >/dev/null 2>&1
      ) 9>/tmp/coder-apt.lock
      echo "[SSH] OpenSSH server installed"
    fi

    HOSTKEYS_DIR="$HOME/.persist/ssh/hostkeys"
    mkdir -p "$HOSTKEYS_DIR" 2>/dev/null || sudo mkdir -p "$HOSTKEYS_DIR"
    sudo chown -R $(id -u):$(id -g) "$HOME/.persist/ssh" 2>/dev/null || true
    chmod 700 "$HOME/.persist/ssh"

    if [ ! -f "$HOSTKEYS_DIR/ssh_host_ed25519_key" ]; then
      echo "[SSH] Generating persistent host keys..."
      sudo ssh-keygen -t ed25519 -f "$HOSTKEYS_DIR/ssh_host_ed25519_key" -N "" >/dev/null 2>&1
      sudo ssh-keygen -t rsa -b 4096 -f "$HOSTKEYS_DIR/ssh_host_rsa_key" -N "" >/dev/null 2>&1
      echo "[SSH] Host keys generated"
    fi
    sudo chmod 600 "$HOSTKEYS_DIR"/ssh_host_* 2>/dev/null

    sudo mkdir -p /etc/ssh /var/run/sshd
    sudo tee /etc/ssh/sshd_config >/dev/null <<SSHD_CFG
Port ${local.ssh_internal}
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
UsePAM yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem sftp /usr/lib/openssh/sftp-server
HostKey $HOSTKEYS_DIR/ssh_host_ed25519_key
HostKey $HOSTKEYS_DIR/ssh_host_rsa_key
AllowUsers coder
SSHD_CFG

    echo "coder:${local.ssh_password}" | sudo chpasswd 2>/dev/null

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/known_hosts"
    chmod 644 "$HOME/.ssh/known_hosts"

    for host in github.com gitlab.com bitbucket.org; do
      if ! grep -q "$host" "$HOME/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan -H "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
      fi
    done

    sudo pkill sshd 2>/dev/null || true
    sleep 1
    sudo /usr/sbin/sshd -f /etc/ssh/sshd_config 2>/dev/null
    sleep 1

    if pgrep sshd >/dev/null; then
      echo "[SSH] SSH server started on internal port ${local.ssh_internal}"
    else
      echo "[SSH] WARNING: SSH daemon failed to start"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SSH] CONNECTION INFO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Connect:  ssh -p ${local.ssh_port} coder@${var.host_ip}"
    echo "  Password: ${local.ssh_password}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT
}

# =============================================================================
# KOTTSTER ADMIN PANEL (inlined from kottster-admin module)
# =============================================================================

resource "coder_script" "kottster" {
  agent_id           = coder_agent.main.id
  display_name       = "Kottster Admin"
  icon               = "/icon/database.svg"
  run_on_start       = true
  start_blocks_login = false

  script = <<-SCRIPT
    #!/bin/bash
    set -e

    KOTTSTER_DIR="${local.kottster_dir}"
    PORT="${local.kottster_port}"
    LOG_FILE="/tmp/kottster.log"
    PID_FILE="/tmp/kottster.pid"

    echo "[KOTTSTER] Starting Kottster admin panel..."

    # Wait for npm install to fully complete (marker file written after npm install in startup_script)
    INSTALL_MARKER="$KOTTSTER_DIR/.install_complete"
    WAITED=0
    while [ ! -f "$INSTALL_MARKER" ] && [ $WAITED -lt 300 ]; do
      sleep 3
      WAITED=$((WAITED + 3))
    done

    if [ ! -f "$INSTALL_MARKER" ]; then
      echo "[KOTTSTER] WARNING: Kottster install did not complete within 5 minutes."
      echo "[KOTTSTER] Check startup script logs."
      exit 1
    fi

    echo "[KOTTSTER] Install complete, waiting 5s for filesystem to settle..."
    sleep 5

    # Kill previous instance
    if [ -f "$PID_FILE" ]; then
      OLD_PID=$(cat "$PID_FILE")
      kill -0 "$OLD_PID" 2>/dev/null && kill "$OLD_PID" 2>/dev/null || true
      sleep 1
    fi

    cd "$KOTTSTER_DIR"
    export PATH="$KOTTSTER_DIR/node_modules/.bin:/usr/local/bin:/usr/bin:/bin:$PATH"

    # Start Kottster in dev mode (background)
    nohup node "$KOTTSTER_DIR/node_modules/@kottster/cli/dist/index.js" dev > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 5

    if kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
      echo "[KOTTSTER] Running on port $PORT (PID: $(cat $PID_FILE))"
      echo "[KOTTSTER] Admin URL: ${local.admin_url}"

      # ── Auto-initialize Kottster app ──
      # Wait for the API server (port 5481) to be ready
      API_PORT=5481
      API_WAITED=0
      while ! curl -s -o /dev/null -w "" "http://localhost:$API_PORT/" 2>/dev/null && [ $API_WAITED -lt 30 ]; do
        sleep 2
        API_WAITED=$((API_WAITED + 2))
      done

      # Check if app needs initialization (kottster-app.json is empty {})
      APP_SCHEMA=$(cat "$KOTTSTER_DIR/kottster-app.json" 2>/dev/null | tr -d '[:space:]')
      if [ "$APP_SCHEMA" = "{}" ]; then
        echo "[KOTTSTER] Initializing app with admin credentials..."
        INIT_RESULT=$(curl -s -X POST "http://localhost:$API_PORT/internal-api?action=initApp" \
          -H "Content-Type: application/json" \
          -d "{\"name\":\"Database Admin\",\"rootUsername\":\"admin\",\"rootPassword\":\"${local.db_password}\"}" 2>&1)

        if echo "$INIT_RESULT" | grep -q '"status":"success"'; then
          echo "[KOTTSTER] App initialized successfully"
          echo "[KOTTSTER] Login: admin / (workspace password)"
        else
          echo "[KOTTSTER] WARNING: App initialization failed: $INIT_RESULT"
          echo "[KOTTSTER] You may need to complete setup manually in the browser"
        fi
      else
        echo "[KOTTSTER] App already initialized"
      fi
    else
      echo "[KOTTSTER] Failed to start. Check $LOG_FILE"
      cat "$LOG_FILE" 2>/dev/null | tail -10
    fi
  SCRIPT
}

# =============================================================================
# PREVIEW LINK
# =============================================================================

resource "coder_app" "kottster" {
  agent_id     = coder_agent.main.id
  slug         = "kottster"
  display_name = "Database Admin"
  icon         = "/icon/database.svg"
  url          = local.admin_url
  external     = true
  order        = 10
}

# =============================================================================
# WORKSPACE CONTAINER
# =============================================================================

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  depends_on = [docker_container.database]

  name     = local.container_name
  image    = docker_image.workspace.image_id
  hostname = local.workspace_name

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]

  networks_advanced {
    name = "coder-network"
  }

  # SSH port (only mapped if SSH enabled)
  dynamic "ports" {
    for_each = local.ssh_enabled ? [local.ssh_port] : []
    content {
      internal = local.ssh_internal
      external = ports.value
    }
  }

  # Traefik labels for Kottster admin panel
  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.docker.network"
    value = "coder-network"
  }
  labels {
    label = "traefik.http.routers.${local.admin_router}.rule"
    value = "Host(`${local.workspace_name}-admin.${var.base_domain}`)"
  }
  labels {
    label = "traefik.http.routers.${local.admin_router}.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.${local.admin_router}.tls"
    value = "true"
  }
  labels {
    label = "traefik.http.services.${local.admin_router}.loadbalancer.server.port"
    value = "${local.kottster_port}"
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

output "db_engine" {
  value = local.db_engine
}

output "admin_url" {
  value = local.admin_url
}

output "connection_string" {
  value     = local.connection_info
  sensitive = true
}
