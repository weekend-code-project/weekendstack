# WeekendStack Credentials & Setup Guide

## Overview

This guide documents the credential management system and first-time setup procedures for all services in the WeekendStack.

**Last Updated:** February 12, 2026

---

## Quick Start

### 1. Generate Configuration

```bash
# Create .env with auto-generated secrets
./tools/env-template-gen.sh

# Validate configuration
./tools/validate-env.sh
```

### 2. Customize Required Values

Edit `.env` and set:
- `COMPUTER_NAME` - Your hostname
- `HOST_IP` - Docker host IP address
- `BASE_DOMAIN` - External domain (e.g., example.com)
- `DEFAULT_ADMIN_EMAIL` - Your admin email
- `TZ` - Your timezone
- `PUID`/`PGID` - Your user/group ID (`id -u` and `id -g`)
- `SSH_KEY_DIR` - Path to your SSH keys

### 3. Deploy Services

```bash
# Start all services
docker compose --profile all up -d

# Or start specific profiles
docker compose --profile dev --profile ai up -d
```

### 4. Complete First-Time Setup

Follow the checklist in **Section: First-Time Setup Checklist** below.

---

## Credential Categories

### Category 1: ENV-Based Authentication

These services support credential configuration via environment variables. Admin accounts are auto-created on first startup using values from `.env`.

**Login Credentials:** Use `${DEFAULT_ADMIN_EMAIL}` / `${DEFAULT_ADMIN_PASSWORD}` (or service-specific overrides)

| Service | Admin User | Admin Password | Database Password |
|---------|------------|----------------|-------------------|
| **NocoDB** | `${DEFAULT_ADMIN_EMAIL}` | `${DEFAULT_ADMIN_PASSWORD}` | `${NOCODB_DB_PASS}` |
| **Paperless-ngx** | `${DEFAULT_ADMIN_USER}` | `${DEFAULT_ADMIN_PASSWORD}` | `${PAPERLESS_DB_PASS}` |
| **NetBox** | `${NETBOX_SUPERUSER}` | `${NETBOX_SUPERUSER_PASSWORD}` | `${NETBOX_DB_PASSWORD}` |
| **WUD** | `admin` | `${DEFAULT_ADMIN_PASSWORD}` | N/A |
| **N8N** | Disabled by default | N/A | `${N8N_DB_PASS}` |
| **Activepieces** | Web signup | N/A | `${ACTIVEPIECES_DB_PASS}` |
| **Postiz** | `${DEFAULT_ADMIN_EMAIL}` | `${DEFAULT_ADMIN_PASSWORD}` | `${POSTIZ_DB_PASS}` |
| **Immich** | Create via web | N/A | `${IMMICH_DB_PASSWORD}` |

**Access URLs:**
- NocoDB: http://nocodb.lab
- Paperless: http://paperless.lab  
- NetBox: http://netbox.lab
- WUD: http://wud.lab
- Postiz: http://postiz.lab
- Immich: http://immich.lab

---

### Category 2: First-Time Setup Required

These services require web-based account creation on first access. **No environment variables** control user credentials—you create accounts directly in the web UI.

#### AI Services

| Service | URL | Setup Process |
|---------|-----|---------------|
| **Open WebUI** | http://open-webui.lab | First signup becomes admin |
| **AnythingLLM** | http://anythingllm.lab | Setup wizard on first visit |
| **LibreChat** | http://librechat.lab | Registration enabled, create account |

#### Productivity Services

| Service | URL | Setup Process |
|---------|-----|---------------|
| **Focalboard** | http://focalboard.lab | First signup becomes admin |
| **Trilium** | http://trilium.lab | Set password on first access |
| **Vikunja** | http://vikunja.lab | First registration becomes admin |
| **FileBrowser** | http://filebrowser.lab | Default: `admin` / Random password (check logs) |
| **Hoarder** | http://hoarder.lab | Setup wizard |
| **ByteStash** | http://bytestash.lab | Create account |
| **Docmost** | http://docmost.lab | Create admin account |

#### Personal Services

| Service | URL | Setup Process |
|---------|-----|---------------|
| **Vaultwarden** | http://vault.lab | First signup (becomes admin) |
| **Mealie** | http://mealie.lab | First signup becomes admin |
| **Firefly III** | http://firefly.lab | Create account on first visit |
| **wger** | http://wger.lab | Registration enabled |

#### Media Services

| Service | URL | Setup Process |
|---------|-----|---------------|
| **Kavita** | http://kavita.lab | Create admin account on first visit |
| **Navidrome** | http://navidrome.lab | First user becomes admin |

#### Automation Services

| Service | URL | Setup Process |
|---------|-----|---------------|
| **Home Assistant** | http://homeassistant.lab | Setup wizard on first access |
| **Node-RED** | http://nodered.lab | No auth by default (enable in settings) |

#### Development Services

| Service | URL | Setup Process | Notes |
|---------|-----|---------------|-------|
| **Coder** | http://coder.lab:7080 | Create admin on first visit | |
| **Gitea** | http://gitea.lab | Installation wizard | |
| **GitLab** | http://gitlab.lab | Root password in logs | Check container logs for initial password |
| **Guacamole** | http://guacamole.lab | Default: `guacadmin` / `guacadmin` | **CHANGE IMMEDIATELY!** |

#### Monitoring Services

| Service | URL | Setup Process |
|---------|-----|---------------|
| **Uptime Kuma** | http://uptime.lab | First signup becomes admin |
| **Portainer** | http://portainer.lab:9443 | Create admin on first access |
| **Duplicati** | http://duplicati.lab | Set password on first access |

---

### Category 3: No Authentication

Services accessible without login (public or uses Traefik auth for external access only):

| Service | URL | Auth Method |
|---------|-----|-------------|
| **Glance** | http://glance.lab | Public dashboard |
| **IT-Tools** | http://it-tools.lab | Traefik auth (external only) |
| **Excalidraw** | http://excalidraw.lab | Traefik auth (external only) |
| **Dozzle** | http://dozzle.lab | Public (local network) |
| **Netdata** | http://netdata.lab | Public (local network) |
| **Traefik** | http://traefik.lab:8081 | Public dashboard (insecure mode) |
| **Ollama** | http://ollama.lab:11434 | API service (no web UI) |
| **LocalAI** | http://localai.lab | API service |
| **Link Router** | Internal | Go links service |

---

### Category 4: System Authentication

Services using system-level or SSH authentication:

| Service | Port | Authentication |
|---------|------|----------------|
| **Cockpit** | 9090 | SSH credentials (same as host) |
| **Pi-hole Web** | 8088 | Password: `${PIHOLE_WEBPASSWORD}` |

---

## First-Time Setup Checklist

After deploying services, complete setup for all active services:

### ENV-Based (Login Immediately)

- [ ] **NocoDB** → http://nocodb.lab
  - Login: `admin@example.com` / (your `DEFAULT_ADMIN_PASSWORD`)
  
- [ ] **Paperless** → http://paperless.lab
  - Login: `admin` / (your `DEFAULT_ADMIN_PASSWORD`)
  
- [ ] **NetBox** → http://netbox.lab
  - Login: `admin` / (your `DEFAULT_ADMIN_PASSWORD`)

### First-Time Setup Required (Visit to Configure)

**High Priority (Essential Services):**

- [ ] **Vaultwarden** → http://vault.lab
  - Create your account (first signup = admin)
  - **After setup:** Set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in `.env`
  
- [ ] **Home Assistant** → http://homeassistant.lab
  - Complete setup wizard
  
- [ ] **Portainer** → http://portainer.lab:9443
  - Create admin account

**AI & Development:**

- [ ] **Open WebUI** → http://open-webui.lab
  - First signup = admin
  
- [ ] **Coder** → http://coder.lab:7080
  - Create admin account
  
- [ ] **Gitea** → http://gitea.lab
  - Complete installation wizard
  - Use database credentials from `.env`

- [ ] **GitLab** → http://gitlab.lab
  - Check logs for root password: `docker compose logs gitlab | grep "Password:"`
  - Login as `root` with that password

**Personal & Productivity:**

- [ ] **Immich** → http://immich.lab
  - Create your account
  
- [ ] **Mealie** → http://mealie.lab
  - First signup = admin
  
- [ ] **Navidrome** → http://navidrome.lab
  - Create admin account
  
- [ ] **Kavita** → http://kavita.lab
  - Create admin account
  
- [ ] **FileBrowser** → http://filebrowser.lab
  - Check logs: `docker compose logs filebrowser | grep "password"`
  - Login as `admin` with generated password
  - **Change password immediately**

**Security Critical:**

- [ ] **Guacamole** → http://guacamole.lab
  - **Default:** `guacadmin` / `guacadmin`
  - **⚠️  CHANGE IMMEDIATELY after first login!**
  - Go to Settings → Users → guacadmin → Change Password

---

## Password Generation Reference

### Standard Password (32 characters)
```bash
openssl rand -hex 32
```
**Used for:** Admin passwords, database passwords

### JWT Secret (64 characters)
```bash
openssl rand -hex 64
```
**Used for:** Session tokens, authentication secrets

### Encryption Key (32 hex characters / 16 bytes)
```bash
openssl rand -hex 16
```
**Used for:** Data encryption (Activepieces requires exactly this)

### App Key (Base64, 32 characters)
```bash
openssl rand -base64 32
```
**Used for:** Firefly III app key

### Special: Gitea Internal Token
```bash
openssl rand -hex 105
```
**Used for:** Gitea internal communications

---

## Security Best Practices

### 1. Change Default Credentials

**Immediately after setup:**
- Change any default passwords (especially Guacamole: `guacadmin`)
- Update admin email from `admin@example.com` to your real email
- Review all ENV-based service credentials

### 2. Disable Public Signups

After creating your accounts, disable signups:

```bash
# Edit .env
VAULTWARDEN_SIGNUPS_ALLOWED=false
LIBRECHAT_ALLOW_REGISTRATION=false
# (Add others as needed)

# Restart services
docker compose up -d vaultwarden librechat
```

### 3. Enable Multi-Factor Authentication

Enable MFA where supported:
- **Vaultwarden:** Built-in TOTP/U2F support
- **Home Assistant:** Settings → Your Account → Multi-factor Authentication
- **Gitea:** Settings → Security → Two-Factor Authentication
- **GitLab:** Profile → Account → Two-Factor Authentication

### 4. Regular Password Rotation

Set a reminder to rotate critical passwords:
- Database passwords: Every 90 days
- Admin passwords: Every 90 days
- Service API keys: Every 180 days

### 5. Secure Traefik Auth

The `DEFAULT_TRAEFIK_AUTH_PASS` protects external access to services without built-in auth. Use a strong password:

```bash
# Generate strong password
openssl rand -hex 32

# Test external access requires auth
curl -u admin:wrongpass https://it-tools.yourdomain.com
# Should return 401 Unauthorized
```

### 6. Backup Credentials

Store `.env` securely:
```bash
# Encrypt .env for backup
gpg -c .env
# Creates .env.gpg

# To restore
gpg .env.gpg
```

**⚠️  Never commit `.env` to git!** (It's in `.gitignore`)

---

## Troubleshooting

### Can't Login to Service

**ENV-based services:**
1. Check `.env` file for correct credentials
2. Restart service: `docker compose restart <service>`
3. Check logs: `docker compose logs <service>`
4. Verify database connection (if applicable)

**First-time setup services:**
1. Clear browser cache/cookies
2. Check if account was already created
3. Reset by deleting service volume:
   ```bash
   docker compose down <service>
   docker volume rm weekendstack_<service>-data
   docker compose up -d <service>
   ```

### Forgot Password

**ENV-based services:**
- Check `.env` for `DEFAULT_ADMIN_PASSWORD`
- If changed, update `.env` and restart service

**First-time setup services:**
- Most have password reset features in UI
- Or reset via database/volume deletion (loses data!)

### Service Won't Start

```bash
# Check logs
docker compose logs <service> --tail 50

# Common issues:
# - Database not ready → wait and restart
# - Port conflict → check PORTS in .env
# - Permission error → check PUID/PGID
```

### FileBrowser Random Password Lost

```bash
# Check logs for password
docker compose logs filebrowser | grep "password"

# If not found, delete volume and restart
docker compose stop filebrowser
docker volume rm weekendstack_filebrowser-<volume-name>
docker compose up -d filebrowser
docker compose logs filebrowser | grep "password"
```

---

##Credential Storage Locations

### Environment Variables
- **File:** `.env` (root of project)
- **Template:** `.env.example` (documented template)
- **⚠️  Security:** `.env` is gitignored - DO NOT COMMIT

### Database Credentials
- **PostgreSQL databases:** Each service has isolated database
- **Location:** Docker volumes (e.g., `weekendstack_nocodb-db-data`)
- **Backup:** Use service-specific backup procedures

### User Accounts
- **Stored:** Service-specific databases/volumes
- **Backup:** 
  - Export from service UI (where available)
  - Backup Docker volumes:
    ```bash
    docker run --rm -v weekendstack_<service>-data:/data \
      -v $(pwd):/backup alpine \
      tar czf /backup/<service>-backup.tar.gz /data
    ```

---

## Quick Reference: Common Credentials

```bash
# Default Admin (ENV-based services)
Email:    admin@example.com (customize in .env)
User:     admin
Password: <generated in .env>

# Traefik Auth (External access)
User:     admin
Password: <generated in .env>

# Database Template
User:     dbuser
Password: <generated per service>

# Pi-hole
Password: <generated in .env: PIHOLE_WEBPASSWORD>
URL:      http://pihole.lab:8088/admin
```

---

## Migration & Backup

### Before Major Changes

```bash
# Backup configuration
cp .env .env.backup.$(date +%Y%m%d)
cp .env.example .env.example.backup.$(date +%Y%m%d)

# Export service data
docker compose exec paperless-ngx document_exporter /usr/src/paperless/export
# ... repeat for other services

# Backup volumes
docker run --rm -v weekendstack_paperless-db-data:/data \
  -v $(pwd)/backups:/backup alpine \
  tar czf /backup/paperless-db.tar.gz /data
```

### Restore Procedure

```bash
# Restore .env
cp .env.backup.YYYYMMDD .env

# Restore volumes
docker volume create weekendstack_paperless-db-data
docker run --rm -v weekendstack_paperless-db-data:/data \
  -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/paperless-db.tar.gz -C /data

# Start services
docker compose --profile all up -d
```

---

## Support & Documentation

- **Project README:** `/README.md`
- **Service Guides:** `/docs/*-setup.md`
- **Validation Script:** `./tools/validate-env.sh`
- **Generation Script:** `./tools/env-template-gen.sh`

**Service-Specific Documentation:**
- Each service in `/docs/<service>-setup.md`
- Official docs linked in each setup guide

---

**Generated by:** WeekendStack Credential Consolidation Project  
**Purpose:** Standardize authentication across 73+ services  
**Security Level:** Production-ready with proper password generation
