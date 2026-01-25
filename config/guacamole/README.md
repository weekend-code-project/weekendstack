# Guacamole Configuration

This directory is mounted to `/config` in the Guacamole container.

## Initial Setup

The Guacamole database schema needs to be initialized once. After starting the services for the first time:

1. Generate the SQL initialization script:
   ```bash
   docker run --rm guacamole/guacamole:latest /opt/guacamole/bin/initdb.sh --postgres > initdb.sql
   ```

2. Import the schema into the database:
   ```bash
   docker exec -i guacamole-db psql -U guacamole -d guacamole < initdb.sql
   ```

3. Access Guacamole at:
   - Local: https://guacamole.lab
   - External: https://guacamole.weekendcodeproject.dev (requires basic auth)

4. Login with default credentials:
   - Username: `guacadmin`
   - Password: `guacadmin`
   - **Change this immediately!**

## Configuration Files

- `guacamole.properties` - Main configuration (optional, environment variables preferred)
- `extensions/` - Additional Guacamole extensions (.jar files)

## User Management

All users are managed through the Guacamole web interface:
- Settings → Users → New User
- Assign connections to specific users
- Set permissions and groups

## Adding Connections

1. Login as admin
2. Settings → Connections → New Connection
3. Configure protocol (SSH/RDP/VNC)
4. Set hostname (use Tailscale IPs for remote machines)
5. Assign to users

## Tailscale Access

Guacamole can access any machine on your Tailscale network:
- Use Tailscale IP addresses in connection configs
- Example: `100.x.x.x` for Tailscale nodes
- No additional network configuration needed
