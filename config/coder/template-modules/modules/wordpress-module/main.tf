terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# MODULE: WordPress Setup
# =============================================================================
# DESCRIPTION:
#   Installs PHP, Apache, and WordPress with automatic database configuration.
#   Presents clean WordPress install screen on first access.

variable "php_version" {
  type        = string
  description = "PHP version to install (8.3, 8.2, 8.1, 8.0, 7.4)"
}

variable "db_host" {
  type        = string
  description = "MySQL database host"
}

variable "db_name" {
  type        = string
  description = "MySQL database name"
}

variable "db_user" {
  type        = string
  description = "MySQL database user"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "MySQL database password"
}

variable "wp_url" {
  type        = string
  description = "WordPress site URL"
}

variable "workspace_name" {
  type        = string
  description = "Workspace name for logging"
}

locals {
  setup_script = <<-EOT
    # WORDPRESS SETUP START
    set +e
    
    LOG_FILE="$HOME/wordpress-setup.log"
    echo "[WORDPRESS] Starting setup at $(date)" > "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    # Wait for MySQL to be ready
    echo "[WORDPRESS] Waiting for MySQL database..." | tee -a "$LOG_FILE"
    for i in {1..30}; do
      if docker exec coder-${var.workspace_name}-mysql mysqladmin ping -h localhost --silent; then
        echo "[WORDPRESS] ✓ MySQL is ready" | tee -a "$LOG_FILE"
        break
      fi
      echo "[WORDPRESS] Waiting for MySQL ($i/30)..." | tee -a "$LOG_FILE"
      sleep 2
    done
    
    # Install PHP and required extensions
    echo "[WORDPRESS] Installing PHP ${var.php_version}..." | tee -a "$LOG_FILE"
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo apt-get install -y software-properties-common >> "$LOG_FILE" 2>&1
    sudo add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1
    sudo apt-get update >> "$LOG_FILE" 2>&1
    
    sudo apt-get install -y \
      php${var.php_version} \
      php${var.php_version}-cli \
      php${var.php_version}-fpm \
      php${var.php_version}-mysql \
      php${var.php_version}-curl \
      php${var.php_version}-gd \
      php${var.php_version}-mbstring \
      php${var.php_version}-xml \
      php${var.php_version}-xmlrpc \
      php${var.php_version}-zip \
      php${var.php_version}-imagick \
      apache2 \
      libapache2-mod-php${var.php_version} \
      mysql-client \
      unzip \
      curl >> "$LOG_FILE" 2>&1
    
    echo "[WORDPRESS] ✓ PHP ${var.php_version} installed" | tee -a "$LOG_FILE"
    php -v | head -1 | tee -a "$LOG_FILE"
    
    # Configure Apache
    echo "[WORDPRESS] Configuring Apache..." | tee -a "$LOG_FILE"
    sudo a2enmod rewrite >> "$LOG_FILE" 2>&1
    sudo a2enmod php${var.php_version} >> "$LOG_FILE" 2>&1
    
    # Download WordPress
    WP_DIR="/home/coder/workspace/wordpress"
    mkdir -p "$WP_DIR"
    cd "$WP_DIR"
    
    if [ ! -f wp-config.php ]; then
      echo "[WORDPRESS] Downloading WordPress..." | tee -a "$LOG_FILE"
      curl -O https://wordpress.org/latest.tar.gz >> "$LOG_FILE" 2>&1
      tar -xzf latest.tar.gz --strip-components=1 >> "$LOG_FILE" 2>&1
      rm latest.tar.gz
      echo "[WORDPRESS] ✓ WordPress downloaded" | tee -a "$LOG_FILE"
      
      # Create wp-config.php
      echo "[WORDPRESS] Configuring wp-config.php..." | tee -a "$LOG_FILE"
      cp wp-config-sample.php wp-config.php
      
      # Update database configuration
      sed -i "s/database_name_here/${var.db_name}/" wp-config.php
      sed -i "s/username_here/${var.db_user}/" wp-config.php
      sed -i "s/password_here/${var.db_password}/" wp-config.php
      sed -i "s/localhost/${var.db_host}/" wp-config.php
      
      # Generate security keys
      KEYS=$(curl -sL https://api.wordpress.org/secret-key/1.1/salt/)
      # Use a more reliable delimiter for sed
      echo "$KEYS" > /tmp/wp-keys.txt
      sed -i "/AUTH_KEY/,/NONCE_SALT/d" wp-config.php
      sed -i "/\/\*\*#@-\*\//r /tmp/wp-keys.txt" wp-config.php
      rm /tmp/wp-keys.txt
      
      # Add site URL configuration
      cat >> wp-config.php <<'EOF'

// Force WordPress to use the correct URL
define('WP_HOME', getenv('WP_URL'));
define('WP_SITEURL', getenv('WP_URL'));

// Allow WordPress behind a reverse proxy
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
EOF
      
      echo "[WORDPRESS] ✓ wp-config.php created" | tee -a "$LOG_FILE"
    else
      echo "[WORDPRESS] wp-config.php already exists, skipping download" | tee -a "$LOG_FILE"
    fi
    
    # Set permissions
    sudo chown -R www-data:www-data "$WP_DIR"
    sudo chmod -R 755 "$WP_DIR"
    
    # Configure Apache virtual host
    echo "[WORDPRESS] Configuring Apache virtual host..." | tee -a "$LOG_FILE"
    sudo tee /etc/apache2/sites-available/wordpress.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot $WP_DIR
    
    <Directory $WP_DIR>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog $${APACHE_LOG_DIR}/wordpress-error.log
    CustomLog $${APACHE_LOG_DIR}/wordpress-access.log combined
</VirtualHost>
EOF
    
    sudo a2dissite 000-default >> "$LOG_FILE" 2>&1
    sudo a2ensite wordpress >> "$LOG_FILE" 2>&1
    
    # Start Apache
    echo "[WORDPRESS] Starting Apache..." | tee -a "$LOG_FILE"
    sudo service apache2 start >> "$LOG_FILE" 2>&1
    
    echo "[WORDPRESS] ✓ Setup complete!" | tee -a "$LOG_FILE"
    echo "[WORDPRESS] Visit ${var.wp_url} to complete WordPress installation" | tee -a "$LOG_FILE"
    echo ""
  EOT
}

output "setup_script" {
  description = "WordPress installation and configuration script"
  value       = local.setup_script
}

output "metadata_blocks" {
  description = "Metadata blocks for WordPress status"
  value = [
    {
      display_name = "PHP Version"
      script       = "php -v | head -1 || echo 'Not installed'"
      interval     = 300
      timeout      = 5
    },
    {
      display_name = "WordPress Status"
      script       = "curl -s -o /dev/null -w '%%{http_code}' http://localhost || echo 'N/A'"
      interval     = 60
      timeout      = 5
    },
    {
      display_name = "MySQL Status"
      script       = "docker exec coder-${var.workspace_name}-mysql mysqladmin ping -h localhost --silent && echo 'Running' || echo 'Stopped'"
      interval     = 60
      timeout      = 5
    }
  ]
}
