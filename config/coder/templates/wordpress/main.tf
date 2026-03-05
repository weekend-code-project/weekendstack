# =============================================================================
# WORDPRESS TEMPLATE
# =============================================================================
# A WordPress development workspace with MariaDB, phpMyAdmin, and Apache.
#
# Features:
#   - MariaDB 10.11 sidecar container with persistent data
#   - WordPress auto-install with configurable PHP version
#   - phpMyAdmin for database management
#   - Apache web server on the preview port
#   - Code-server web IDE
#   - SSH server access
#   - External preview via Traefik
#
# This template does NOT include:
#   - Git integration (WordPress development workspace)
#   - Node.js / language runtimes
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

data "coder_parameter" "php_version" {
  name         = "php_version"
  display_name = "PHP Version"
  description  = "PHP version for WordPress"
  type         = "string"
  default      = "8.3"
  mutable      = false
  order        = 10

  option {
    name  = "PHP 8.3 (Latest)"
    value = "8.3"
  }
  option {
    name  = "PHP 8.2"
    value = "8.2"
  }
  option {
    name  = "PHP 8.1"
    value = "8.1"
  }
}

data "coder_parameter" "db_password" {
  name         = "db_password"
  display_name = "Database Password"
  description  = "MySQL/MariaDB password. Leave blank to auto-generate."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 100
}

data "coder_parameter" "wp_auto_install" {
  name         = "wp_auto_install"
  display_name = "Auto-Install WordPress"
  description  = "Automatically create the WordPress admin user on startup. Disable to use the web installer."
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 101
}

data "coder_parameter" "wp_admin_user" {
  name         = "wp_admin_user"
  display_name = "WP Admin Username"
  description  = "WordPress admin username. Leave blank for 'admin'."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 102
}

data "coder_parameter" "wp_admin_password" {
  name         = "wp_admin_password"
  display_name = "WP Admin Password"
  description  = "WordPress admin password. Leave blank to auto-generate."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 103
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
  wordpress_dir    = "/home/coder/workspace/wordpress"

  php_version              = data.coder_parameter.php_version.value
  preview_port             = "80"  # Apache listens on 80
  external_preview_enabled = "true"
  workspace_password       = data.coder_parameter.workspace_password.value

  # Tunnel detection for external app URLs
  tunnel_enabled = startswith(data.coder_workspace.me.access_url, "https://")
  pma_url        = local.tunnel_enabled ? "https://${local.workspace_name}-pma.${var.base_domain}" : "http://${local.workspace_name}-pma.${var.host_ip}.nip.io"
  ssh_enabled              = data.coder_parameter.enable_ssh.value
  ssh_password             = local.workspace_password != "" ? local.workspace_password : random_password.ssh_fallback.result
  ssh_port                 = try(module.ssh_server[0].ssh_port, 0)

  mysql_container   = "mysql-${local.workspace_name}"
  pma_container     = "pma-${local.workspace_name}"
  git_cli           = data.coder_parameter.git_cli.value
  wp_admin_user     = data.coder_parameter.wp_admin_user.value != "" ? data.coder_parameter.wp_admin_user.value : "admin"
  wp_admin_password = data.coder_parameter.wp_admin_password.value != "" ? data.coder_parameter.wp_admin_password.value : random_password.wp_admin_fallback.result
  wp_auto_install   = data.coder_parameter.wp_auto_install.value
  db_password       = data.coder_parameter.db_password.value != "" ? data.coder_parameter.db_password.value : random_password.db_password.result
}

# =============================================================================
# PASSWORDS
# =============================================================================

resource "random_password" "ssh_fallback" {
  length  = 16
  special = false
}

resource "random_password" "wp_admin_fallback" {
  length  = 16
  special = false
}

resource "random_password" "db_password" {
  length  = 32
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

resource "docker_image" "mysql" {
  name         = "mariadb:10.11"
  keep_locally = true
}

resource "docker_image" "phpmyadmin" {
  name         = "phpmyadmin:latest"
  keep_locally = true
}

# =============================================================================
# PERSISTENT STORAGE
# =============================================================================

resource "docker_volume" "home" {
  name = "coder-${local.owner_name}-${local.workspace_name}-home"
}

resource "docker_volume" "mysql_data" {
  name = "coder-${local.owner_name}-${local.workspace_name}-mysql"
}

# =============================================================================
# MYSQL CONTAINER
# =============================================================================

resource "docker_container" "mysql" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.mysql.image_id
  name     = local.mysql_container
  hostname = local.mysql_container

  env = [
    "MYSQL_ROOT_PASSWORD=${local.db_password}",
    "MYSQL_DATABASE=wordpress",
    "MYSQL_USER=wordpress",
    "MYSQL_PASSWORD=${local.db_password}",
  ]

  networks_advanced {
    name    = "coder-network"
    aliases = [local.mysql_container, "mysql"]
  }

  volumes {
    volume_name    = docker_volume.mysql_data.name
    container_path = "/var/lib/mysql"
  }

  healthcheck {
    test         = ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
    interval     = "5s"
    timeout      = "3s"
    retries      = 30
    start_period = "30s"
  }

  labels {
    label = "glance.hide"
    value = "true"
  }

  restart = "unless-stopped"
}

# =============================================================================
# PHPMYADMIN CONTAINER
# =============================================================================

resource "docker_container" "phpmyadmin" {
  count      = data.coder_workspace.me.start_count
  image      = docker_image.phpmyadmin.image_id
  name       = local.pma_container
  depends_on = [docker_container.mysql]

  env = [
    "PMA_HOST=${local.mysql_container}",
    "PMA_USER=root",
    "PMA_PASSWORD=${local.db_password}",
    "UPLOAD_LIMIT=50M",
  ]

  networks_advanced {
    name = "coder-network"
  }

  # Traefik labels for phpMyAdmin
  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.docker.network"
    value = "coder-network"
  }
  labels {
    label = "traefik.http.routers.${local.workspace_name}-pma.rule"
    value = "Host(`${local.workspace_name}-pma.${var.base_domain}`)"
  }
  labels {
    label = "traefik.http.routers.${local.workspace_name}-pma.entrypoints"
    value = "websecure"
  }
  labels {
    label = "traefik.http.routers.${local.workspace_name}-pma.tls"
    value = "true"
  }
  labels {
    label = "traefik.http.services.${local.workspace_name}-pma.loadbalancer.server.port"
    value = "80"
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
    echo "[STARTUP] WordPress workspace initialization..."
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
    display_name = "Apache"
    key          = "apache"
    script       = "if pgrep apache2 >/dev/null; then echo 'Running'; else echo 'Stopped'; fi"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "MySQL"
    key          = "mysql"
    script       = "echo 'Container: ${local.mysql_container}'"
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
  create_preview_app       = false
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
# WORDPRESS INSTALL (coder_script)
# =============================================================================

resource "coder_script" "wordpress_install" {
  agent_id           = coder_agent.main.id
  display_name       = "WordPress Install"
  icon               = "/icon/database.svg"
  run_on_start       = true
  start_blocks_login = true  # Must complete before workspace is usable

  script = <<-SCRIPT
    #!/bin/bash
    set -e

    WORDPRESS_DIR="${local.wordpress_dir}"
    MYSQL_HOST="${local.mysql_container}"
    DB_PASSWORD="${local.db_password}"
    PHP_VERSION="${local.php_version}"
    BASE_DOMAIN="${var.base_domain}"
    WORKSPACE_NAME="${local.workspace_name}"
    WP_ADMIN_USER="${local.wp_admin_user}"
    WP_ADMIN_PASSWORD="${local.wp_admin_password}"
    WP_AUTO_INSTALL="${local.wp_auto_install}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[WORDPRESS] Installing PHP $PHP_VERSION + Apache + WordPress..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Skip if already installed
    if [ -f "$WORDPRESS_DIR/wp-config.php" ] && pgrep apache2 >/dev/null 2>&1; then
      echo "[WORDPRESS] WordPress already installed, restarting Apache..."
      sudo service apache2 restart 2>/dev/null || true
      echo "[WORDPRESS] Done (already installed)"
      exit 0
    fi

    # ── Install PHP + Apache ──
    echo "[WORDPRESS] Installing packages..."
    (
      flock -w 300 9 || { echo "[WORDPRESS] Could not acquire apt lock"; exit 1; }
      sudo apt-get update -qq >/dev/null 2>&1

      # Add PHP PPA for version selection
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common >/dev/null 2>&1
      sudo add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
      sudo apt-get update -qq >/dev/null 2>&1

      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        "php$PHP_VERSION" \
        "php$PHP_VERSION-mysql" \
        "php$PHP_VERSION-curl" \
        "php$PHP_VERSION-gd" \
        "php$PHP_VERSION-xml" \
        "php$PHP_VERSION-mbstring" \
        "php$PHP_VERSION-zip" \
        apache2 "libapache2-mod-php$PHP_VERSION" \
        >/dev/null 2>&1
    ) 9>/tmp/coder-apt.lock

    echo "[WORDPRESS] PHP $PHP_VERSION and Apache installed"

    # ── Configure Apache ──
    sudo a2enmod rewrite >/dev/null 2>&1

    # Set up WordPress directory
    sudo mkdir -p "$WORDPRESS_DIR"
    sudo chmod o+x /home/coder /home/coder/workspace
    sudo chown -R www-data:www-data "$WORDPRESS_DIR"

    # ── Download WordPress (if not already present) ──
    if [ ! -f "$WORDPRESS_DIR/wp-login.php" ]; then
      echo "[WORDPRESS] Downloading WordPress..."
      cd "$WORDPRESS_DIR"
      sudo -u www-data curl -sO https://wordpress.org/latest.tar.gz
      sudo -u www-data tar -xzf latest.tar.gz --strip-components=1
      sudo -u www-data rm -f latest.tar.gz
      echo "[WORDPRESS] WordPress downloaded"
    fi

    # ── Configure wp-config.php ──
    if [ ! -f "$WORDPRESS_DIR/wp-config.php" ]; then
      echo "[WORDPRESS] Creating wp-config.php..."
      sudo -u www-data cp "$WORDPRESS_DIR/wp-config-sample.php" "$WORDPRESS_DIR/wp-config.php"
      sudo -u www-data sed -i "s/database_name_here/wordpress/" "$WORDPRESS_DIR/wp-config.php"
      sudo -u www-data sed -i "s/username_here/wordpress/" "$WORDPRESS_DIR/wp-config.php"
      sudo -u www-data sed -i "s/password_here/$DB_PASSWORD/" "$WORDPRESS_DIR/wp-config.php"
      sudo -u www-data sed -i "s/localhost/$MYSQL_HOST/" "$WORDPRESS_DIR/wp-config.php"

      # Add reverse proxy HTTPS detection before "That's all" line
      # Traefik terminates SSL and forwards HTTP — WordPress needs to trust X-Forwarded-Proto
      sudo tee /tmp/wp-proxy-fix.php >/dev/null <<'PHPFIX'

/* Use the real hostname from the reverse proxy (Coder/Traefik) */
if (isset($_SERVER['HTTP_X_FORWARDED_HOST'])) {
    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];
}
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('FORCE_SSL_ADMIN', false);

/* Dynamic URL: adapt to the access method (Coder subdomain proxy, .lab, or tunnel) */
if (isset($_SERVER['HTTP_HOST']) && !defined('WP_CLI')) {
    $scheme = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https' : 'http';
    define('WP_HOME', $scheme . '://' . $_SERVER['HTTP_HOST']);
    define('WP_SITEURL', $scheme . '://' . $_SERVER['HTTP_HOST']);
}
PHPFIX
      # Insert before "That's all, stop editing!" line
      sudo -u www-data sed -i "/That's all, stop editing/r /tmp/wp-proxy-fix.php" "$WORDPRESS_DIR/wp-config.php"
      sudo rm -f /tmp/wp-proxy-fix.php

      echo "[WORDPRESS] wp-config.php configured (with reverse proxy support)"
    fi

    # ── Configure Apache VirtualHost ──
    sudo tee /etc/apache2/sites-available/wordpress.conf >/dev/null <<VHOST
<VirtualHost *:80>
    DocumentRoot $WORDPRESS_DIR
    <Directory $WORDPRESS_DIR>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
VHOST

    sudo a2dissite 000-default >/dev/null 2>&1 || true
    sudo a2ensite wordpress >/dev/null 2>&1

    # ── Wait for MySQL ──
    echo "[WORDPRESS] Waiting for MySQL ($MYSQL_HOST)..."
    MAX_WAIT=180
    WAITED=0
    while true; do
      # Try DNS resolution first, then TCP connection
      if getent hosts "$MYSQL_HOST" >/dev/null 2>&1; then
        if timeout 2 bash -c "echo >/dev/tcp/$MYSQL_HOST/3306" 2>/dev/null; then
          echo "[WORDPRESS] MySQL is accepting connections ($${WAITED}s)"
          # Give MySQL a moment to finish initializing grants
          sleep 3
          break
        fi
        [ $(($${WAITED} % 10)) -eq 0 ] && [ $WAITED -gt 0 ] && echo "[WORDPRESS] MySQL DNS resolved, waiting for port 3306 ($${WAITED}s)..."
      else
        [ $(($${WAITED} % 10)) -eq 0 ] && [ $WAITED -gt 0 ] && echo "[WORDPRESS] Waiting for MySQL DNS resolution ($${WAITED}s)..."
      fi
      sleep 2
      WAITED=$((WAITED + 2))
      if [ $WAITED -ge $MAX_WAIT ]; then
        echo "[WORDPRESS] WARNING: MySQL not ready after $${MAX_WAIT}s"
        echo "[WORDPRESS] DNS check: $(getent hosts $MYSQL_HOST 2>&1 || echo 'FAILED')"
        echo "[WORDPRESS] Continuing anyway — Apache will start but WordPress may show db error"
        break
      fi
    done

    # ── Start Apache ──
    echo "[WORDPRESS] Starting Apache..."
    sudo service apache2 restart

    if pgrep apache2 >/dev/null 2>&1; then
      echo "[WORDPRESS] Apache is running"
    else
      echo "[WORDPRESS] WARNING: Apache failed to start"
    fi

    # ── Auto-install WordPress via WP-CLI ──
    if [ "$WP_AUTO_INSTALL" = "true" ]; then
      if ! command -v wp >/dev/null 2>&1; then
        echo "[WORDPRESS] Installing WP-CLI..."
        curl -so /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x /tmp/wp-cli.phar
        sudo mv /tmp/wp-cli.phar /usr/local/bin/wp
        echo "[WORDPRESS] WP-CLI installed"
      fi

      # Check if WordPress is already installed
      if sudo -u www-data wp core is-installed --path="$WORDPRESS_DIR" 2>/dev/null; then
        echo "[WORDPRESS] WordPress already installed, skipping setup"
      else
        echo "[WORDPRESS] Running WordPress auto-install..."
        sudo -u www-data wp core install \
          --path="$WORDPRESS_DIR" \
          --url="http://localhost" \
          --title="WordPress Dev" \
          --admin_user="$WP_ADMIN_USER" \
          --admin_password="$WP_ADMIN_PASSWORD" \
          --admin_email="admin@$BASE_DOMAIN" \
          --skip-email
        echo "[WORDPRESS] WordPress installed successfully"
      fi

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "[WORDPRESS] CREDENTIALS"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  WP Admin:    $WP_ADMIN_USER"
      echo "  WP Pass:     $WP_ADMIN_PASSWORD"
      echo "  DB Pass:     $DB_PASSWORD"
      echo "  Site:        (use preview buttons in Coder)"
      echo "  Admin:       (use WP Admin button in Coder)"
      echo "  phpMyAdmin:  (use phpMyAdmin button in Coder)"
      echo "  External:    https://$WORKSPACE_NAME.$BASE_DOMAIN (if tunnel enabled)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
      echo "[WORDPRESS] Auto-install disabled — use external preview to run the web installer"
      echo "[WORDPRESS] DB Pass: $DB_PASSWORD"
    fi
  SCRIPT
}

# =============================================================================
# PREVIEW LINKS
# =============================================================================

resource "coder_app" "wp_admin" {
  agent_id     = coder_agent.main.id
  slug         = "wp-admin"
  display_name = "Admin"
  icon         = "/icon/widgets.svg"
  url          = "${module.traefik_routing.workspace_url}/wp-admin"
  external     = true
  order        = 2
}

resource "coder_app" "wordpress" {
  agent_id     = coder_agent.main.id
  slug         = "wordpress"
  display_name = "Preview"
  icon         = "/icon/desktop.svg"
  url          = module.traefik_routing.workspace_url
  external     = true
  order        = 3
}

resource "coder_app" "phpmyadmin" {
  agent_id     = coder_agent.main.id
  slug         = "phpmyadmin"
  display_name = "phpMyAdmin"
  icon         = "/icon/database.svg"
  url          = local.pma_url
  external     = true
  order        = 20
}

# =============================================================================
# WORKSPACE CONTAINER
# =============================================================================

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  depends_on = [docker_container.mysql]

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

output "wordpress_url" {
  description = "WordPress access via Coder proxy"
  value       = "Use WP Admin button in Coder dashboard"
}

output "wordpress_external_url" {
  description = "WordPress external URL (via tunnel)"
  value       = "https://${local.workspace_name}.${var.base_domain}"
}

output "phpmyadmin_url" {
  description = "phpMyAdmin external URL (via tunnel)"
  value       = "https://${local.workspace_name}-pma.${var.base_domain}"
}
