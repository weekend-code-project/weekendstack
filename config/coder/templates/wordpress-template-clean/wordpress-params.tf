# =============================================================================
# WordPress Configuration Parameters
# =============================================================================

# PHP Version Selection
data "coder_parameter" "php_version" {
  name         = "php_version"
  display_name = "PHP Version"
  description  = "Select PHP version for WordPress"
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
  option {
    name  = "PHP 8.0"
    value = "8.0"
  }
  option {
    name  = "PHP 7.4"
    value = "7.4"
  }
}

# Local to hold PHP version metadata
locals {
  php_metadata = {
    "PHP Version" = {
      value = data.coder_parameter.php_version.value
      icon  = "🐘"
    }
  }
  
  # WordPress installation script
  wordpress_install_script = <<-EOT
#!/bin/bash
echo '[WordPress] 🐘 Installing PHP ${data.coder_parameter.php_version.value} and Apache...'

# Install PHP and Apache
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  php${data.coder_parameter.php_version.value} \
  php${data.coder_parameter.php_version.value}-mysql \
  php${data.coder_parameter.php_version.value}-curl \
  php${data.coder_parameter.php_version.value}-gd \
  php${data.coder_parameter.php_version.value}-xml \
  php${data.coder_parameter.php_version.value}-mbstring \
  php${data.coder_parameter.php_version.value}-zip \
  apache2 libapache2-mod-php${data.coder_parameter.php_version.value} \
  > /dev/null 2>&1

# Enable Apache modules
sudo a2enmod rewrite > /dev/null 2>&1

# Configure Apache for port 80
sudo sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/apache2/ports.conf

# Set up WordPress directory
sudo mkdir -p /home/coder/workspace/wordpress
sudo chown -R www-data:www-data /home/coder/workspace/wordpress
cd /home/coder/workspace/wordpress

# Download WordPress
echo '[WordPress] 📥 Downloading WordPress...'
sudo -u www-data curl -sO https://wordpress.org/latest.tar.gz
sudo -u www-data tar -xzf latest.tar.gz --strip-components=1
sudo -u www-data rm latest.tar.gz

# Create wp-config.php
echo '[WordPress] ⚙️  Configuring WordPress...'
sudo -u www-data cp wp-config-sample.php wp-config.php
sudo -u www-data sed -i "s/database_name_here/wordpress/" wp-config.php
sudo -u www-data sed -i "s/username_here/wordpress/" wp-config.php
sudo -u www-data sed -i "s/password_here/${random_password.db_password.result}/" wp-config.php
sudo -u www-data sed -i "s/localhost/mysql-${data.coder_workspace.me.name}/" wp-config.php

# Configure Apache VirtualHost
sudo tee /etc/apache2/sites-available/wordpress.conf > /dev/null <<EOF
<VirtualHost *:80>
    DocumentRoot /home/coder/workspace/wordpress
    <Directory /home/coder/workspace/wordpress>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

sudo a2dissite 000-default > /dev/null 2>&1
sudo a2ensite wordpress > /dev/null 2>&1

# Start Apache
sudo service apache2 start > /dev/null 2>&1

echo '[WordPress] ✅ WordPress ready at https://${lower(data.coder_workspace.me.name)}.${var.base_domain}'
EOT
}
