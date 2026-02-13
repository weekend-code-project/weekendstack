#!/usr/bin/with-contenv bash
# FileBrowser initialization script for s6-overlay
# Sets admin password to DEFAULT_ADMIN_PASSWORD from environment

DB_PATH="/database/filebrowser.db"
PASSWORD="${DEFAULT_ADMIN_PASSWORD:-admin}"

echo "[filebrowser-init] Starting FileBrowser password configuration..."

# Wait a moment for DB to be ready
sleep 1

# Check if database exists
if [ -f "$DB_PATH" ]; then
    echo "[filebrowser-init] Database exists, updating admin password..."
    filebrowser -d "$DB_PATH" users update admin --password "$PASSWORD" 2>/dev/null && \
        echo "[filebrowser-init] ✓ Admin password updated" || \
        echo "[filebrowser-init] Note: Admin user may not exist yet or password already set"
else
    echo "[filebrowser-init] Creating new database with admin user..."
    filebrowser -d "$DB_PATH" config init
    filebrowser -d "$DB_PATH" users add admin "$PASSWORD" --perm.admin && \
        echo "[filebrowser-init] ✓ Admin user created with DEFAULT_ADMIN_PASSWORD"
fi

echo "[filebrowser-init] Username: admin"
echo "[filebrowser-init] Password: (using DEFAULT_ADMIN_PASSWORD from .env)"
echo "[filebrowser-init] Initialization complete"
