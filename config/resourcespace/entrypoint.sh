#!/bin/bash

CONFIG_FILE="/var/www/html/include/config.php"
DB_HOST="${RESOURCESPACE_DB_HOST:-resourcespace-db}"
DB_NAME="${RESOURCESPACE_DB_NAME:-resourcespace}"
DB_USER="${RESOURCESPACE_DB_USER:-resourcespace}"
DB_PASS="${RESOURCESPACE_DB_PASS:-resourcespace_password_2024}"

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

// Dynamically determine base URL from request
\$protocol = (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ? 'https' : 'http';
\$host = isset(\$_SERVER['HTTP_HOST']) ? \$_SERVER['HTTP_HOST'] : 'resourcespace.lab';
\$baseurl = \$protocol . '://' . \$host;
\$baseurl_short = 'pages';
\$storagedir = '/var/www/html/filestore';

\$scramble_key = '$SCRAMBLE_KEY';
\$api_scramble_key = '$API_KEY';

\$applicationname = 'ResourceSpace DAM';
\$email_from = 'resourcespace@localhost';
\$email_notify = 'admin@localhost';

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

echo "========================================="
echo "ResourceSpace is ready!"
echo "URL: http://resourcespace.lab/"
echo "Complete account setup in the web UI."
echo "========================================="

# Wait for Apache process
wait $APACHE_PID
