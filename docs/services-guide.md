# WeekendStack Services Guide

Complete reference for all services in the WeekendStack self-hosted platform.

> 🔐 **Default Credentials:** See [default-credentials.md](default-credentials.md) for all default login credentials and access URLs.

## Quick Start

```bash
# Start all services
docker compose --profile all up -d

# Start specific profiles
docker compose --profile dev --profile ai up -d

# View running services
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

---

## Service Categories

| Category | Services | Profile |
|----------|----------|---------|
| **Core** | Glance, Traefik, Cloudflare Tunnel, Error Pages | `core` |
| **Development** | Coder, Gitea, GitLab | `dev` |
| **AI** | Open WebUI, SearXNG | `ai` |
| **Productivity** | n8n, Paperless, NocoDB, Activepieces, Hoarder, File Browser, Focalboard, Trilium, Vikunja, Vaultwarden | `productivity` |
| **Automation** | Home Assistant, Node-RED | `automation` |
| **Media** | Immich, Kavita, Navidrome | `media` |
| **Personal** | Mealie, Firefly III, wger | `personal` |
| **Monitoring** | Cockpit, Dozzle, Watchtower, Uptime Kuma, Netdata, Duplicati, Portainer | `monitoring` |
| **Networking** | Pi-Hole | `networking` |

---

## Core Services

### Glance - Dashboard / Start Page
**Port:** 8098 | **Local Domain:** `glance.lab`

YAML-configured dashboard used as the main start page.

Setup:
- [docs/glance-setup.md](docs/glance-setup.md)
- [docs/go-links-setup.md](docs/go-links-setup.md)

### Traefik - Reverse Proxy
**Ports:** 80/443 | **Local Dashboard:** `http://traefik.lab/dashboard/`

Routes external traffic to internal services with automatic HTTPS.

**Key Variables:**
```env
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443
```

### Error Pages - Custom 404/Error Pages
**Port:** 8080 (internal)

Custom error pages for Traefik routing failures and backend errors.

**Key Variables:**
```env
ERROR_PAGES_THEME=ghost
ERROR_PAGES_SHOW_DETAILS=false
```

**Features:**
- Custom 404 pages for non-existent routes
- Fallback for all Traefik routing errors
- 11 available themes (ghost, l7-light, l7-dark, shuffle, noise, hacker-terminal, cats, lost-in-space, app-down, connection, orient)

**Setup:**
- [docs/error-pages-setup.md](error-pages-setup.md)

### Cloudflare Tunnel
Secure tunnel for external access without exposing ports.

**Configuration:** `config/cloudflare/config.yml`

---

## Development Services

### Coder - Cloud Development Environment
**Port:** 7080 | **Domain:** `coder.${BASE_DOMAIN}`

Browser-based VS Code workspaces with Docker templates.

**Access:**
- URL: `http://192.168.2.50:7080`
- Initial Setup: Create admin account on first access

**Key Variables:**
```env
CODER_HTTP_PORT=7080
CODER_DOMAIN=coder.${BASE_DOMAIN}
POSTGRES_USER=coder_admin
POSTGRES_PASSWORD=secure_password_change_me
```

**Setup:**
- [docs/coder-setup.md](coder-setup.md)
- [docs/coder-templates-guide.md](coder-templates-guide.md)

### Gitea - Git Repository
**Port:** 7001 (Web), 2222 (SSH) | **Domain:** `gitea.${BASE_DOMAIN}`

Lightweight Git hosting with Actions support.

**Access:**
- URL: `http://192.168.2.50:7001`
- Initial Setup: Create admin account on first access
- SSH: Port 2222

**Key Variables:**
```env
GITEA_PORT=7001
GITEA_SSH_PORT=2222
GITEA_SECRET_KEY=gitea-secret-key-change-me
GITEA_DBUSER=gitea
GITEA_DBPASS=gitea_db_password_change_me
```

### GitLab CE - Full DevOps Platform
**Port:** 8929 (Web), 2224 (SSH) | **Domain:** `gitlab.${BASE_DOMAIN}`

Complete DevOps platform with CI/CD, container registry, and more.

> ⚠️ **Note:** Requires HTTPS. Only accessible via Cloudflare tunnel.

**Access:**
- URL: `http://192.168.2.50:8929` (requires HTTPS in production)
- Username: `root`
- Password: Get from container:
  ```bash
  docker exec gitlab cat /etc/gitlab/initial_root_password
  ```
- SSH: Port 2224

**Key Variables:**
```env
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2224
GITLAB_MEMORY_LIMIT=4g
```

**Setup:**
- [docs/gitlab-setup.md](gitlab-setup.md)

---

## AI Services

### Open WebUI - AI Chat Interface
**Port:** 3000 | **Domain:** `chat.${BASE_DOMAIN}`

Chat interface for Ollama models. Requires Ollama running on host.

**Access:**
- URL: `http://192.168.2.50:3000`
- Initial Setup: Create account on first access (first user becomes admin)

**Prerequisites:**
```bash
# Install Ollama on host
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull llama2
```

**Key Variables:**
```env
OPENWEBUI_PORT=3000
OLLAMA_HOST=http://host.docker.internal:11434
WEBUI_SECRET_KEY=secure-chat-key-change-me
```

**Setup:**
- [docs/ai-services-setup.md](ai-services-setup.md)

### SearXNG - Private Search
**Port:** 4000 | **Domain:** `search.${BASE_DOMAIN}`

Privacy-respecting metasearch engine.

**Access:**
- URL: `http://192.168.2.50:4000`
- Username: `searx`
- Password: `searxng-password-change-me`

**Key Variables:**
```env
SEARXNG_PORT=4000
SEARXNG_AUTH_USER=searx
SEARXNG_AUTH_PASSWORD=searxng-password-change-me
SEARXNG_SECRET_KEY=searxng-secret-key-change-me
```

---

## Productivity Services

### File Browser - Web File Manager
**Port:** 8096

Browse and manage the repo `files/` directory.

**Access:**
- URL: `http://192.168.2.50:8096`
- Username: `admin`
- Password: `admin`

**Key Variables:**
```env
FILEBROWSER_PORT=8096
```

**Setup:**
- [docs/filebrowser-setup.md](filebrowser-setup.md)

### Hoarder - Bookmark Manager
**Port:** 3030

Bookmark manager with AI-powered tagging and full-text search.

**Access:**
- URL: `http://192.168.2.50:3030`
- Initial Setup: Create account on first access

**Key Variables:**
```env
HOARDER_PORT=3030
HOARDER_NEXTAUTH_SECRET=hoarder-nextauth-secret-change-me
HOARDER_MEILI_MASTER_KEY=hoarder-meili-master-key-change-me
```

**Setup:**
- [docs/hoarder-setup.md](hoarder-setup.md)

### n8n - Workflow Automation
**Port:** 5678 | **Domain:** `n8n.${BASE_DOMAIN}`

Visual workflow automation like Zapier.

**Access:**
- URL: `http://192.168.2.50:5678`
- Initial Setup: Create owner account on first access

**Key Variables:**
```env
N8N_PORT=5678
N8N_DBUSER=n8n
N8N_DBPASS=n8n_password_change_me
```

**Setup:**
- [docs/nodered-setup.md](nodered-setup.md)

### Paperless-ngx - Document Management
**Port:** 8082 | **Domain:** `paperless.${BASE_DOMAIN}`

Scan, index, and archive documents with OCR.

**Access:**
- URL: `http://192.168.2.50:8082`
- Username: `admin`
- Password: `secure_paperless_password_change_me`

**Key Variables:**
```env
PAPERLESS_PORT=8082
PAPERLESS_ADMIN_USER=admin
PAPERLESS_ADMIN_PASSWORD=secure_paperless_password_change_me
PAPERLESS_DBUSER=paperless
PAPERLESS_DBPASS=paperless_db_password_change_me
```

**Directories:**
- `files/paperless/consume/` - Drop documents here for auto-import
- `files/paperless/media/` - Stored documents

**Setup:**
- [docs/paperless-integration.md](paperless-integration.md)

### NocoDB - Database Platform
**Port:** 8090 | **Domain:** `nocodb.${BASE_DOMAIN}`

Airtable alternative for collaborative databases.

**Access:**
- URL: `http://192.168.2.50:8090`
- Initial Setup: Create account on first access
- Password (if set): `secure_nocodb_password_change_me`

**Key Variables:**
```env
NOCODB_PORT=8090
NOCODB_ADMIN_PASSWORD=secure_nocodb_password_change_me
NOCODB_JWT_SECRET=nocodb-jwt-secret-change-me
NOCODB_DBUSER=nocodb
NOCODB_DBPASS=nocodb_password_change_me
```

### Activepieces - Workflow Automation
**Port:** 8087 | **Domain:** `activepieces.${BASE_DOMAIN}`

Open-source Zapier alternative.

**Access:**
- URL: `http://192.168.2.50:8087`
- Initial Setup: Create account on first access

**Key Variables:**
```env
ACTIVEPIECES_PORT=8087
# Generate with: openssl rand -hex 16
ACTIVEPIECES_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef
ACTIVEPIECES_JWT_SECRET=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
ACTIVEPIECES_DBUSER=activepieces
ACTIVEPIECES_DBPASS=activepieces_password_change_me
```

### Focalboard - Project Management
**Port:** 8097 | **Domain:** `focalboard.${BASE_DOMAIN}`

Trello/Notion-style project boards.

**Access:**
- URL: `http://192.168.2.50:8097`
- Initial Setup: Create account on first access

**Key Variables:**
```env
FOCALBOARD_PORT=8097
```

**Setup:**
- [docs/focalboard-setup.md](focalboard-setup.md)

### Trilium - Note Taking
**Port:** 8085 | **Domain:** `trilium.${BASE_DOMAIN}`

Hierarchical note-taking with powerful organization.

**Access:**
- URL: `http://192.168.2.50:8085`
- Initial Setup: Set password on first access

**Key Variables:**
```env
TRILIUM_PORT=8085
```

**Setup:**
- [docs/trilium-setup.md](trilium-setup.md)

### Vikunja - Task Management
**Port:** 3456 | **Domain:** `vikunja.${BASE_DOMAIN}`

Todoist-like task management.

**Access:**
- URL: `http://192.168.2.50:3456`
- Initial Setup: Create account on first access

**Key Variables:**
```env
VIKUNJA_PORT=3456
VIKUNJA_JWT_SECRET=vikunja-jwt-secret-change-me
```

**Setup:**
- [docs/vikunja-setup.md](vikunja-setup.md)

### Vaultwarden - Password Manager
**Port:** 8222 | **Domain:** `vault.${BASE_DOMAIN}`

Bitwarden-compatible password manager.

> ⚠️ **Note:** Requires HTTPS (WebCrypto API). Only works via Cloudflare tunnel.

**Access:**
- URL: `http://192.168.2.50:8222` (use HTTPS in production)
- Initial Setup: Create account on first access

**Key Variables:**
```env
VAULTWARDEN_PORT=8222
VAULTWARDEN_SIGNUPS_ALLOWED=true
```

**Setup:**
- [docs/vaultwarden-setup.md](vaultwarden-setup.md)

---

## Automation Services

### Home Assistant - Smart Home
**Port:** 8123 | **Domain:** `home.${BASE_DOMAIN}`

Smart home automation platform.

**Access:**
- URL: `http://192.168.2.50:8123`
- Initial Setup: Create account on first access

**Configuration:** `files/homeassistant/`

**Setup:**
- [docs/homeassistant-setup.md](homeassistant-setup.md)

### Node-RED - Flow Programming
**Port:** 1880 | **Domain:** `nodered.${BASE_DOMAIN}`

Visual programming for IoT and automation.

**Access:**
- URL: `http://192.168.2.50:1880`
- Auth: None by default (can enable in settings)

**Key Variables:**
```env
NODERED_PORT=1880
```

**Setup:**
- [docs/nodered-setup.md](nodered-setup.md)

---

## Media Services

### Immich - Photo Management
**Port:** 2283 | **Domain:** `immich.${BASE_DOMAIN}`

Google Photos alternative with ML-powered features.

**Access:**
- URL: `http://192.168.2.50:2283`
- Initial Setup: Create admin account on first access

**Key Variables:**
```env
IMMICH_PORT=2283
IMMICH_DB_USER=immich
IMMICH_DB_PASSWORD=immich_password_change_me
```

**Upload Directory:** `files/immich/upload/`

**Setup:**
- [docs/immich-setup.md](immich-setup.md)

### Kavita - eBook Reader
**Port:** 5000 | **Domain:** `kavita.${BASE_DOMAIN}`

Self-hosted digital library for books, comics, manga.

**Access:**
- URL: `http://192.168.2.50:5000`
- Initial Setup: Create account on first access

**Key Variables:**
```env
KAVITA_PORT=5000
```

**Library Path:** `files/kavita/library/`

**Setup:**
- [docs/kavita-setup.md](kavita-setup.md)

### Navidrome - Music Streaming
**Port:** 4533 | **Domain:** `music.${BASE_DOMAIN}`

Personal music streaming server.

**Access:**
- URL: `http://192.168.2.50:4533`
- Initial Setup: Create admin account on first access

**Key Variables:**
```env
NAVIDROME_PORT=4533
```

**Music Path:** `files/navidrome/music/`

**Setup:**
- [docs/navidrome-setup.md](navidrome-setup.md)

---

## Personal Services

### Mealie - Meal Planning
**Port:** 9925 | **Domain:** `mealie.${BASE_DOMAIN}`

Recipe manager and meal planner.

**Access:**
- URL: `http://192.168.2.50:9925`
- Initial Setup: Create account on first access

**Key Variables:**
```env
MEALIE_PORT=9925
```

**Setup:**
- [docs/mealie-setup.md](mealie-setup.md)

### Firefly III - Personal Finance
**Port:** 8086 | **Domain:** `firefly.${BASE_DOMAIN}`

Personal finance manager.

**Access:**
- URL: `http://192.168.2.50:8086`
- Initial Setup: Create account on first access

**Key Variables:**
```env
FIREFLY_PORT=8086
# Must be exactly 32 characters
FIREFLY_APP_KEY=SomeRandomStringOf32CharsExactly
```

**Setup:**
- [docs/firefly-setup.md](firefly-setup.md)

### wger - Workout Tracker
**Port:** 8089 | **Domain:** `wger.${BASE_DOMAIN}`

Workout and fitness tracker with exercise database.

**Access:**
- URL: `http://192.168.2.50:8089`
- Initial Setup: Create account on first access

**Key Variables:**
```env
WGER_PORT=8089
WGER_SECRET_KEY=wger-secret-key-change-me
```

**Setup:**
- [docs/wger-setup.md](wger-setup.md)

---

## Monitoring Services

### Cockpit - Server Administration
**Port:** 9090

Web-based server administration interface.

**Access:**
- URL: `http://192.168.2.50:9090`
- Auth: System user credentials (Linux users)
- **Note:** Local network only (not exposed externally)

**Key Variables:**
```env
COCKPIT_PORT=9090
```

### Dozzle - Docker Logs
**Port:** 9999 | **Domain:** `dozzle.${BASE_DOMAIN}` (local only recommended)

Real-time Docker log viewer.

**Access:**
- URL: `http://192.168.2.50:9999`
- Auth: None (read-only)

**Key Variables:**
```env
DOZZLE_PORT=9999
```

### Uptime Kuma - Service Monitoring
**Port:** 3001 | **Domain:** `uptime.${BASE_DOMAIN}`

Self-hosted uptime monitoring.

### Netdata - System Monitoring
**Port:** 19999 | **Domain:** `netdata.${BASE_DOMAIN}`

Real-time system performance monitoring.

**Access:**
- URL: `http://192.168.2.50:19999`
- Auth: None by default
- **Note:** Local network only (not exposed externally)

**Key Variables:**
```env
NETDATA_PORT=19999
```

**Setup:**
- [docs/monitoring-setup.md](monitoring-setup.md)

### Duplicati - Backups
**Port:** 8200 | **Domain:** `duplicati.${BASE_DOMAIN}`

Encrypted cloud backup solution.

**Access:**
- URL: `http://192.168.2.50:8200`
- Auth: Set password on first access (optional)

**Key Variables:**
```env
DUPLICATI_PORT=8200
DUPLICATI_ENCRYPTION_KEY=duplicati-encryption-key-change-me
```

### Portainer - Container Management
**Port:** 9000 (HTTP), 9443 (HTTPS) | **Domain:** `portainer.${BASE_DOMAIN}`

Docker container management UI.

**Access:**
- URL: `http://192.168.2.50:9000` or `https://192.168.2.50:9443`
- Initial Setup: Create admin account on first access

**Key Variables:**
```env
PORTAINER_PORT=9443
```

### Watchtower - Auto Updates
**Runs in Background**

Automatically updates containers when new images are available.

---

## Networking Services

### Pi-Hole - DNS Ad Blocking
**Port:** 8088 (Web), 53 (DNS) | **Local Only**

Network-wide ad blocking.

**Access:**
- URL: `http://192.168.2.50:8088/admin`
- Password: `pihole-admin-change-me`
- **Note:** Local network only (not exposed externally)

**Key Variables:**
```env
PIHOLE_PORT_WEB=8088
PIHOLE_PORT_DNS=53
PIHOLE_WEBPASSWORD=pihole-admin-change-me
```

**Setup:**
- [docs/pihole-setup.md](pihole-setup.md)

---

## Port Reference

| Port | Service | Notes |
|------|---------|-------|
| 80 | Traefik HTTP | |
| 443 | Traefik HTTPS | |
| 1880 | Node-RED | |
| 2222 | Gitea SSH | |
| 2224 | GitLab SSH | |
| 2283 | Immich | |
| 3000 | Open WebUI | |
| 3001 | Uptime Kuma | |
| 3456 | Vikunja | |
| 4000 | SearXNG | |
| 4533 | Navidrome | |
| 5000 | Kavita | |
| 5353 | Pi-Hole DNS | |
| 5678 | n8n | |
| 7001 | Gitea | |
| 7080 | Coder | |
| 8082 | Paperless | |
| 8085 | Trilium | |
| 8086 | Firefly III | |
| 8087 | Activepieces | |
| 8088 | Pi-Hole Web | |
| 8089 | wger | |
| 8090 | NocoDB | |
| 8097 | Focalboard | |
| 8123 | Home Assistant | |
| 8200 | Duplicati | |
| 8222 | Vaultwarden | HTTPS only |
| 8929 | GitLab | HTTPS only |
| 9090 | Cockpit | Routed locally via `cockpit.lab` |
| 9000 | Portainer | |
| 9925 | Mealie | |
| 9999 | Dozzle | |
| 19999 | Netdata | |
