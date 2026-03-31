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

# ResourceSpace creates include/config.php from its own web installer.
# Do not pre-create it here or the app skips the first-run setup flow.
mkdir -p /var/www/html/include /var/www/html/filestore /var/www/html/upload
chown -R www-data:www-data /var/www/html/include /var/www/html/filestore /var/www/html/upload
chmod -R 775 /var/www/html/include /var/www/html/filestore /var/www/html/upload

# Start Apache in background to allow database initialization
echo "Starting Apache..."
apache2ctl -D FOREGROUND &
APACHE_PID=$!

# Wait for Apache to start
sleep 5

echo "========================================="
echo "ResourceSpace is ready!"
echo "URL: http://resourcespace.lab/"
if [ -f "$CONFIG_FILE" ]; then
    echo "Existing configuration detected. Open the login page to continue."
else
    echo "Complete the first-run installer at /pages/setup.php"
fi
echo "========================================="

# Wait for Apache process
wait $APACHE_PID
