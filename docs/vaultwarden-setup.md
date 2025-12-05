# Vaultwarden Setup Guide

Vaultwarden is a lightweight, self-hosted password manager compatible with Bitwarden clients.

## Access URLs

| Type | URL |
|------|-----|
| Local | http://192.168.2.50:8222 |
| Public | https://vault.weekendcodeproject.dev |

## Starting Vaultwarden

```bash
docker compose --profile core up -d vaultwarden
```

## Initial Setup

1. Navigate to http://192.168.2.50:8222
2. Click "Create Account"
3. Enter your email, master password, and password hint
4. Click "Submit"

### Important Security Notes

- **Master Password**: Use a strong, unique master password. This is the only password you need to remember.
- **Admin Token**: Set `VAULTWARDEN_ADMIN_TOKEN` in `.env` to enable the admin panel at `/admin`
- **Disable Signups**: After creating your account, set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in `.env` to prevent unauthorized registrations

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULTWARDEN_PORT` | 8222 | Host port for web UI |
| `VAULTWARDEN_DOMAIN` | vault.${BASE_DOMAIN} | Domain for Traefik routing |
| `VAULTWARDEN_SIGNUPS_ALLOWED` | true | Allow new account creation |
| `VAULTWARDEN_ADMIN_TOKEN` | (empty) | Token for admin panel access |
| `VAULTWARDEN_MEMORY_LIMIT` | 256m | Container memory limit |

## Admin Panel

To enable the admin panel:

1. Generate a secure token:
   ```bash
   openssl rand -base64 48
   ```

2. Add it to `.env`:
   ```
   VAULTWARDEN_ADMIN_TOKEN=your_generated_token_here
   ```

3. Restart Vaultwarden:
   ```bash
   docker compose --profile core up -d vaultwarden
   ```

4. Access the admin panel at http://192.168.2.50:8222/admin

## Using Bitwarden Clients

Vaultwarden is compatible with all official Bitwarden clients:

### Browser Extensions
1. Install the Bitwarden extension for your browser
2. Before logging in, click the gear icon (Settings)
3. Under "Self-hosted Environment", enter:
   - **Server URL**: `https://vault.weekendcodeproject.dev` (for public access)
   - Or `http://192.168.2.50:8222` (for local access)
4. Save and log in with your credentials

### Desktop App
1. Download Bitwarden from https://bitwarden.com/download/
2. Before logging in, click "Logging in on:" and select "Self-hosted"
3. Enter the server URL and save
4. Log in with your credentials

### Mobile Apps
1. Download Bitwarden from App Store or Google Play
2. Before logging in, tap the settings gear
3. Enter the self-hosted server URL
4. Log in with your credentials

## Data Storage

Vaultwarden stores all data in a Docker volume:
- **Volume**: `weekendstack_vaultwarden-data`
- **Contents**: SQLite database, attachments, RSA keys, icons

## Backup

To backup Vaultwarden data:

```bash
# Create a backup directory
mkdir -p ~/backups/vaultwarden

# Backup the volume
docker run --rm \
  -v weekendstack_vaultwarden-data:/data:ro \
  -v ~/backups/vaultwarden:/backup \
  alpine tar -czf /backup/vaultwarden-$(date +%Y%m%d).tar.gz -C /data .
```

## Restore

```bash
# Stop Vaultwarden
docker compose --profile core stop vaultwarden

# Restore from backup
docker run --rm \
  -v weekendstack_vaultwarden-data:/data \
  -v ~/backups/vaultwarden:/backup \
  alpine sh -c "rm -rf /data/* && tar -xzf /backup/vaultwarden-YYYYMMDD.tar.gz -C /data"

# Start Vaultwarden
docker compose --profile core up -d vaultwarden
```

## Troubleshooting

### Container won't start
```bash
docker logs vaultwarden
```

### Check container health
```bash
docker ps --filter name=vaultwarden
```

### Reset admin token
If you lose your admin token, you can set a new one in `.env` and restart the container.

## Security Recommendations

1. **Use HTTPS only for public access** - Vaultwarden handles sensitive data
2. **Disable signups after setup** - Prevent unauthorized accounts
3. **Set a strong admin token** - Protect the admin panel
4. **Regular backups** - Keep your password vault safe
5. **Enable 2FA** - Add two-factor authentication in your account settings
