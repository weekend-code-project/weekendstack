#!/bin/bash

CONFIG_FILE="/var/www/html/include/config.php"
DB_HOST="resourcespace-db"
DB_NAME="resourcespace"
DB_USER="resourcespace"
DB_PASS="resourcespace_password_2024"

# Wait for database to be ready
echo "Waiting for database..."
while ! mysqladmin ping -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" --silent; do
    sleep 2
done
echo "Database is ready!"

# Check if already configured
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating ResourceSpace configuration..."
    
    # Generate random keys
    SCRAMBLE_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    API_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
    
    # Create config file
    cat > "$CONFIG_FILE" << EOF
<?php
\$mysql_server = '$DB_HOST';
\$mysql_username = '$DB_USER';
\$mysql_password = '$DB_PASS';
\$mysql_db = '$DB_NAME';
\$mysql_bin_path = '/usr/bin';

\$baseurl = 'https://resourcespace.lab';
\$baseurl_short = 'pages';
\$storagedir = '/var/www/html/filestore';

\$scramble_key = '$SCRAMBLE_KEY';
\$api_scramble_key = '$API_KEY';

\$applicationname = 'ResourceSpace DAM';
\$email_from = 'resourcespace@localhost';
\$email_notify = 'admin@localhost';

// Admin account (change these!)
\$default_admin_username = 'admin';
\$default_admin_password = 'resourcespace_admin_2024';
\$default_admin_email = 'admin@localhost';
\$default_admin_fullname = 'Administrator';

// Trust proxy headers for HTTPS
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
}
EOF

    chown www-data:www-data "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    
    echo "Configuration created. Database will initialize on first access."
fi

# Start Apache in background to allow database initialization
echo "Starting Apache..."
apache2ctl -D FOREGROUND &
APACHE_PID=$!

# Wait for Apache to start
sleep 5

# Trigger database initialization
echo "Initializing ResourceSpace database..."
for i in {1..10}; do
    if curl -s http://localhost/ > /dev/null 2>&1; then
        echo "ResourceSpace responding..."
        break
    fi
    sleep 2
done

# Wait for user table to be created
echo "Waiting for database schema..."
for i in {1..20}; do
    if mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'user';" 2>/dev/null | grep -q user; then
        echo "Database schema ready!"
        break
    fi
    sleep 2
done

# Create admin user with proper password hash (bcrypt with HMAC)
echo "Setting up admin user..."
ADMIN_PASS_HASH=$(php -r '
$password = "RSadminresourcespace_admin_2024";
$scramble_key = "'"$SCRAMBLE_KEY"'";
$hmac = hash_hmac("sha256", $password, $scramble_key);
echo password_hash($hmac, PASSWORD_DEFAULT);
')

# Check if admin user exists, if not create it
USER_COUNT=$(mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "SELECT COUNT(*) FROM user WHERE username='admin';" 2>/dev/null)

if [ "$USER_COUNT" = "0" ]; then
    mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" << SQLEOF 2>/dev/null
INSERT INTO user (username, password, fullname, email, usergroup, approved) 
VALUES ('admin', '$ADMIN_PASS_HASH', 'Administrator', 'admin@localhost', 3, 1);
SQLEOF
else
    mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" << SQLEOF 2>/dev/null
UPDATE user SET password='$ADMIN_PASS_HASH' WHERE username='admin' LIMIT 1;
SQLEOF
fi

echo "========================================="
echo "ResourceSpace is ready!"
echo "URL: http://resourcespace.lab/"
echo "Username: admin"
echo "Password: resourcespace_admin_2024"
echo "========================================="

# Wait for Apache process
wait $APACHE_PID
