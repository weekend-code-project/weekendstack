# WeekendStack Services Guide

Complete reference for all services in the WeekendStack self-hosted platform.

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
| **Core** | Glance, Traefik, Cloudflare Tunnel | `core` |
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

### Cloudflare Tunnel
Secure tunnel for external access without exposing ports.

**Configuration:** `config/cloudflare/config.yml`

---

## Development Services

### Coder - Cloud Development Environment
**Port:** 7080 | **Domain:** `coder.${BASE_DOMAIN}`

Browser-based VS Code workspaces with Docker templates.

**Key Variables:**
```env
CODER_HTTP_PORT=7080
CODER_DOMAIN=coder.${BASE_DOMAIN}
POSTGRES_PASSWORD=secure_password_change_me
```

### Gitea - Git Repository
**Port:** 7001 (Web), 2222 (SSH) | **Domain:** `gitea.${BASE_DOMAIN}`

Lightweight Git hosting with Actions support.

**Key Variables:**
```env
GITEA_PORT=7001
GITEA_SSH_PORT=2222
GITEA_SECRET_KEY=gitea-secret-key-change-me
```

### GitLab CE - Full DevOps Platform
**Port:** 8929 (Web), 2224 (SSH) | **Domain:** `gitlab.${BASE_DOMAIN}`

Complete DevOps platform with CI/CD, container registry, and more.

> ⚠️ **Note:** Requires HTTPS. Only accessible via Cloudflare tunnel.

**Key Variables:**
```env
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2224
GITLAB_MEMORY_LIMIT=4g
```

**Get Initial Password:**
```bash
docker exec gitlab cat /etc/gitlab/initial_root_password
```

---

## AI Services

### Open WebUI - AI Chat Interface
**Port:** 3000 | **Domain:** `chat.${BASE_DOMAIN}`

Chat interface for Ollama models. Requires Ollama running on host.

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

### SearXNG - Private Search
**Port:** 4000 | **Domain:** `search.${BASE_DOMAIN}`

Privacy-respecting metasearch engine.

**Key Variables:**
```env
SEARXNG_PORT=4000
SEARXNG_SECRET_KEY=searxng-secret-key-change-me
```

---

## Productivity Services

### File Browser - Repo Files UI
Browse and manage the repo `files/` directory.

Setup:
- [docs/filebrowser-setup.md](docs/filebrowser-setup.md)

### Hoarder (Karakeep) - Bookmark Everything
Bookmark manager with local persistence.

Setup:
- [docs/hoarder-setup.md](docs/hoarder-setup.md)

### n8n - Workflow Automation
**Port:** 5678 | **Domain:** `n8n.${BASE_DOMAIN}`

Visual workflow automation like Zapier.

**Key Variables:**
```env
N8N_PORT=5678
N8N_DBPASS=n8n_password_change_me
```

### Paperless-ngx - Document Management
**Port:** 8082 | **Domain:** `paperless.${BASE_DOMAIN}`

Scan, index, and archive documents with OCR.

**Key Variables:**
```env
PAPERLESS_PORT=8082
PAPERLESS_ADMIN_USER=admin
PAPERLESS_ADMIN_PASSWORD=secure_paperless_password_change_me
```

**Directories:**
- `files/paperless/consume/` - Drop documents here for auto-import
- `files/paperless/media/` - Stored documents

### NocoDB - Database Platform
**Port:** 8090 | **Domain:** `nocodb.${BASE_DOMAIN}`

Airtable alternative for collaborative databases.

**Key Variables:**
```env
NOCODB_PORT=8090
NOCODB_JWT_SECRET=nocodb-jwt-secret-change-me
```

### Activepieces - Workflow Automation
**Port:** 8087 | **Domain:** `activepieces.${BASE_DOMAIN}`

Open-source Zapier alternative.

**Key Variables:**
```env
ACTIVEPIECES_PORT=8087
# Generate with: openssl rand -hex 16
ACTIVEPIECES_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef
```

### Focalboard - Project Management
**Port:** 8097 | **Domain:** `focalboard.${BASE_DOMAIN}`

Trello/Notion-style project boards.

### Trilium - Note Taking
**Port:** 8085 | **Domain:** `trilium.${BASE_DOMAIN}`

Hierarchical note-taking with powerful organization.

### Vikunja - Task Management
**Port:** 3456 | **Domain:** `vikunja.${BASE_DOMAIN}`

Todoist-like task management.

**Key Variables:**
```env
VIKUNJA_PORT=3456
VIKUNJA_JWT_SECRET=vikunja-jwt-secret-change-me
```

### Vaultwarden - Password Manager
**Port:** 8222 | **Domain:** `vault.${BASE_DOMAIN}`

Bitwarden-compatible password manager.

> ⚠️ **Note:** Requires HTTPS (WebCrypto API). Only works via Cloudflare tunnel.

**Key Variables:**
```env
VAULTWARDEN_PORT=8222
VAULTWARDEN_SIGNUPS_ALLOWED=true
```

---

## Automation Services

### Home Assistant - Smart Home
**Port:** 8123 | **Domain:** `home.${BASE_DOMAIN}`

Smart home automation platform.

**Configuration:** `files/homeassistant/`

### Node-RED - Flow Programming
**Port:** 1880 | **Domain:** `nodered.${BASE_DOMAIN}`

Visual programming for IoT and automation.

---

## Media Services

### Immich - Photo Management
**Port:** 2283 | **Domain:** `immich.${BASE_DOMAIN}`

Google Photos alternative with ML-powered features.

**Key Variables:**
```env
IMMICH_PORT=2283
IMMICH_DB_PASSWORD=immich_password_change_me
```

**Upload Directory:** `files/immich/upload/`

### Kavita - eBook Reader
**Port:** 5000 | **Domain:** `kavita.${BASE_DOMAIN}`

Self-hosted digital library for books, comics, manga.

**Library Path:** `files/kavita/library/`

### Navidrome - Music Streaming
**Port:** 4533 | **Domain:** `music.${BASE_DOMAIN}`

Personal music streaming server.

**Music Path:** `files/navidrome/music/`

---

## Personal Services

### Mealie - Meal Planning
**Port:** 9925 | **Domain:** `mealie.${BASE_DOMAIN}`

Recipe manager and meal planner.

### Firefly III - Personal Finance
**Port:** 8086 | **Domain:** `firefly.${BASE_DOMAIN}`

Personal finance manager.

**Key Variables:**
```env
FIREFLY_PORT=8086
# Must be exactly 32 characters
FIREFLY_APP_KEY=SomeRandomStringOf32CharsExactly
```

### wger - Workout Tracker
**Port:** 8089 | **Domain:** `wger.${BASE_DOMAIN}`

Workout and fitness tracker with exercise database.

---

## Monitoring Services

### Dozzle - Docker Logs
**Port:** 9999 | **Domain:** `dozzle.${BASE_DOMAIN}` (local only recommended)

Real-time Docker log viewer.

### Uptime Kuma - Service Monitoring
**Port:** 3001 | **Domain:** `uptime.${BASE_DOMAIN}`

Self-hosted uptime monitoring.

### Netdata - System Monitoring
**Port:** 19999 | **Domain:** `netdata.${BASE_DOMAIN}`

Real-time system performance monitoring.

### Duplicati - Backups
**Port:** 8200 | **Domain:** `duplicati.${BASE_DOMAIN}`

Encrypted cloud backup solution.

**Key Variables:**
```env
DUPLICATI_PORT=8200
DUPLICATI_ENCRYPTION_KEY=duplicati-encryption-key-change-me
```

### Portainer - Container Management
**Port:** 9000 | **Domain:** `portainer.${BASE_DOMAIN}`

Docker container management UI.

### Watchtower - Auto Updates
**Runs in Background**

Automatically updates containers when new images are available.

---

## Networking Services

### Pi-Hole - DNS Ad Blocking
**Port:** 8088 (Web), 5353 (DNS) | **Local Only**

Network-wide ad blocking.

**Key Variables:**
```env
PIHOLE_PORT_WEB=8088
PIHOLE_PORT_DNS=5353
PIHOLE_WEBPASSWORD=pihole-admin-change-me
```

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
