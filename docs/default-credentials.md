# Default Credentials Reference

> **MVP Default Credentials (v0.3.0)**
> 
> For quick MVP testing, all services use consolidated credentials:
> - **Username:** `admin`
> - **Password:** `weekendstack`
> 
> Change these in `.env` before production use!

---

## 🔑 Quick Reference - All Services

| Category | Service | Username | Password | Notes |
|----------|---------|----------|----------|-------|
| **Auth** | Traefik (external) | `admin` | `weekendstack` | Used for services without built-in auth |
| **Database** | PostgreSQL | `admin` | `weekendstack` | Shared DB for Coder, etc. |
| **DNS** | Pi-hole | - | `weekendstack` | Web admin password |
| **Dev** | Gitea | `admin` | `weekendstack` | First-run setup creates account |
| **Dev** | Coder | `admin` | (create on first run) | Create account on first access |
| **Productivity** | Paperless-ngx | `admin` | `weekendstack` | Document management |
| **Productivity** | NocoDB | `admin` | `weekendstack` | Airtable alternative |
| **Productivity** | Activepieces | `admin` | `weekendstack` | Workflow automation |
| **Productivity** | Postiz | `admin@example.com` | `weekendstack` | Social media management |
| **Productivity** | AtroCore | `admin` | `weekendstack` | Digital asset management |
| **Monitoring** | NetBox | `admin` | `weekendstack` | Infrastructure management |
| **Monitoring** | WUD | `admin` | `weekendstack` | Container update monitoring |
| **Media** | Immich | - | - | Create account on first access |
| **Media** | Navidrome | `admin` | `admin` | Music streaming |
| **AI** | Open WebUI | - | - | Create account on first access |
| **AI** | SearXNG | `admin` | `weekendstack` | Privacy search (same as Traefik auth) |

---

## 🚀 MVP Quick Start

1. **Clone and start core services:**
   ```bash
   cd /opt/stacks/weekendstack
   docker network create shared-network 2>/dev/null || true
   docker compose --profile core up -d
   ```

2. **Access services:**
   - Glance Dashboard: http://192.168.2.215:8080 (or http://home.lab via Traefik)
   - Vaultwarden: http://192.168.2.215:8222

3. **Add development tools:**
   ```bash
   docker compose --profile core --profile dev up -d
   ```
   - Coder: http://192.168.2.215:7080
   - Gitea: http://192.168.2.215:7001

4. **Add productivity:**
   ```bash
   docker compose --profile core --profile productivity up -d
   ```

---

## Traefik Authentication (External Access)

All services without built-in authentication use a shared default credential for external access via `*.weekendcodeproject.dev`:

**Username:** `admin`  
**Password:** `weekendstack`

### Services Using Default Auth

These services require the default Traefik credentials when accessed externally:

- **Glance Dashboard** - home.weekendcodeproject.dev
- **IT-Tools** - it-tools.weekendcodeproject.dev  
- **Excalidraw** - excalidraw.weekendcodeproject.dev
- **LocalAI** - localai.weekendcodeproject.dev
- **AnythingLLM** - anythingllm.weekendcodeproject.dev
- **Whisper** - whisper.weekendcodeproject.dev
- **SearXNG** - searxng.weekendcodeproject.dev

### Local Access (No Authentication)

When accessing services via `*.lab` domain on your local network, **no authentication is required** (trusted network pattern).

### Changing the Default Password

1. Update all `*_PASSWORD` and `*_DBPASS` variables in your `.env` file
2. For Traefik auth, generate new bcrypt hash:
   ```bash
   docker run --rm httpd:alpine htpasswd -nbB admin YOUR_NEW_PASSWORD
   ```
3. Update auth files in `config/traefik/auth/` with the new hash (remember to escape `$` as `$$` in YAML)
4. Restart services:
   ```bash
   docker compose --profile all down && docker compose --profile all up -d
   ```

---

## 🌐 Core Services

### Glance - Dashboard
- **URL:** http://192.168.2.50:8098
- **Auth:** None (open access)

### Traefik - Reverse Proxy
- **Dashboard:** http://192.168.2.50/dashboard/ or http://traefik.lab/dashboard/
- **Auth:** None (API access only, no login UI)

---

## 💻 Development Services

### Coder - Cloud Development Environment
- **URL:** http://192.168.2.50:7080
- **Initial Setup:** Create admin account on first access
- **Database:**
  - User: `coder_admin`
  - Password: `secure_password_change_me`

### Gitea - Git Repository
- **URL:** http://192.168.2.50:7001
- **Initial Setup:** Create admin account on first access
- **SSH:** Port 2222
- **Database:**
  - User: `gitea`
  - Password: `gitea_db_password_change_me`

### GitLab - DevOps Platform
- **URL:** http://192.168.2.50:8929
- **Username:** `root`
- **Password:** Get from container:
  ```bash
  docker exec gitlab cat /etc/gitlab/initial_root_password
  ```
- **SSH:** Port 2224
- **Note:** Only accessible via HTTPS tunnel in production

### Docker Registry
- **URL:** http://192.168.2.50:5001
- **Auth:** None (internal use)

---

## 🤖 AI Services

### Open WebUI - AI Chat
- **URL:** http://192.168.2.50:3000
- **Initial Setup:** Create account on first access (first user becomes admin)
- **Note:** Requires Ollama running on host at port 11434

### SearXNG - Private Search
- **URL:** http://192.168.2.50:4000
- **Username:** `searx`
- **Password:** `searxng-password-change-me`

### Stable Diffusion WebUI
- **URL:** http://192.168.2.50:7861
- **Auth:** None by default
- **Note:** Requires NVIDIA GPU

### LocalAI - LLM API Server
- **URL:** http://192.168.2.50:8084
- **Auth:** API-based (no web login)

### AnythingLLM - Document Chat
- **URL:** http://192.168.2.50:3003
- **Initial Setup:** Create account on first access

### Whisper - Speech-to-Text
- **URL:** http://192.168.2.50:9002
- **Auth:** API-based (no web login)

### WhisperX - Enhanced Speech-to-Text
- **URL:** http://192.168.2.50:9001
- **Auth:** API-based (no web login)

### PrivateGPT - Document AI
- **URL:** http://192.168.2.50:8501
- **Auth:** None by default

### LibreChat - Multi-provider Chat
- **URL:** http://192.168.2.50:3080
- **Initial Setup:** Create account on first access

### ComfyUI - Image Generation
- **URL:** http://192.168.2.50:8188
- **Auth:** None by default
- **Note:** Requires NVIDIA GPU

---

## 📋 Productivity Services

### n8n - Workflow Automation
- **URL:** http://192.168.2.50:5678
- **Initial Setup:** Create owner account on first access
- **Database:**
  - User: `n8n`
  - Password: `n8n_password_change_me`

### Paperless-ngx - Document Management
- **URL:** http://192.168.2.50:8082
- **Username:** `admin`
- **Password:** `secure_paperless_password_change_me`
- **Database:**
  - User: `paperless`
  - Password: `paperless_db_password_change_me`

### NocoDB - Database Platform
- **URL:** http://192.168.2.50:8090
- **Initial Setup:** Create account on first access
- **Password (if set):** `secure_nocodb_password_change_me`
- **Database:**
  - User: `nocodb`
  - Password: `nocodb_password_change_me`

### Activepieces - Workflow Automation
- **URL:** http://192.168.2.50:8087
- **Initial Setup:** Create account on first access
- **Database:**
  - User: `activepieces`
  - Password: `activepieces_password_change_me`

### Focalboard - Project Management
- **URL:** http://192.168.2.50:8097
- **Initial Setup:** Create account on first access

### Trilium - Note Taking
- **URL:** http://192.168.2.50:8085
- **Initial Setup:** Set password on first access

### Vikunja - Task Management
- **URL:** http://192.168.2.50:3456
- **Initial Setup:** Create account on first access

### Vaultwarden - Password Manager
- **URL:** http://192.168.2.50:8222 (must use HTTPS in production)
- **Initial Setup:** Create account on first access
- **Note:** WebCrypto requires HTTPS; use tunnel for production

### Postiz - Social Media Manager
- **URL:** http://192.168.2.50:8095
- **Email:** `admin@example.com`
- **Password:** `secure_postiz_password_change_me`
- **Database:**
  - User: `postiz`
  - Password: `postiz_password_change_me`

### File Browser - Web File Manager
- **URL:** http://192.168.2.50:8096
- **Username:** `admin`
- **Password:** `admin`
- **Note:** Scope limited to `./files` directory

### Hoarder - Bookmark Manager
- **URL:** http://192.168.2.50:3030
- **Initial Setup:** Create account on first access

### Docmost - Collaborative Wiki
- **URL:** http://192.168.2.50:3002
- **Initial Setup:** Create account on first access
- **Database:**
  - User: `docmost`
  - Password: `docmost_password_change_me`

### Excalidraw - Whiteboard
- **URL:** http://192.168.2.50:3001
- **Auth:** None (collaborative drawing)

### IT-Tools - Developer Utilities
- **URL:** http://192.168.2.50:8082
- **Auth:** None (utility collection)

### ByteStash - Code Snippets
- **URL:** http://192.168.2.50:5010
- **Initial Setup:** Create account on first access

---

## 🏠 Automation Services

### Home Assistant - Smart Home
- **URL:** http://192.168.2.50:8123
- **Initial Setup:** Create account on first access
- **Config:** `files/homeassistant/`

### Node-RED - Flow Programming
- **URL:** http://192.168.2.50:1880
- **Auth:** None by default (can enable in settings)

---

## 🎬 Media Services

### Immich - Photo Management
- **URL:** http://192.168.2.50:2283
- **Initial Setup:** Create admin account on first access
- **Database:**
  - User: `immich`
  - Password: `immich_password_change_me`

### Kavita - eBook Reader
- **URL:** http://192.168.2.50:5000
- **Initial Setup:** Create account on first access
- **Library:** `files/kavita/library/`

### Navidrome - Music Streaming
- **URL:** http://192.168.2.50:4533
- **Initial Setup:** Create admin account on first access
- **Music:** `files/navidrome/music/`

---

## 👤 Personal Services

### Mealie - Meal Planning
- **URL:** http://192.168.2.50:9925
- **Initial Setup:** Create account on first access

### Firefly III - Personal Finance
- **URL:** http://192.168.2.50:8086
- **Initial Setup:** Create account on first access
- **App Key:** `SomeRandomStringOf32CharsExactly` (must be exactly 32 chars)

### wger - Workout Tracker
- **URL:** http://192.168.2.50:8089
- **Initial Setup:** Create account on first access

---

## 📊 Monitoring Services

### Cockpit - Server Administration
- **URL:** http://192.168.2.50:9090
- **Auth:** System user credentials (Linux users)
- **Note:** Local network only (not exposed externally)

### Dozzle - Docker Logs
- **URL:** http://192.168.2.50:9999
- **Auth:** None (read-only log viewer)

### What's Up Docker (WUD) - Update Manager
- **URL:** http://192.168.2.50:3002
- **Username:** `admin`
- **Password:** `admin`
- **Note:** Local network only (not exposed externally)

### Netdata - System Monitoring
- **URL:** http://192.168.2.50:19999
- **Auth:** None by default
- **Note:** Local network only (not exposed externally)

### Uptime Kuma - Service Monitoring
- **URL:** http://192.168.2.50:3001
- **Initial Setup:** Create admin account on first access

### Duplicati - Backup Solution
- **URL:** http://192.168.2.50:8200
- **Auth:** Set password on first access (optional)

### Portainer - Container Management
- **URL:** http://192.168.2.50:9000 (HTTP) or https://192.168.2.50:9443 (HTTPS)
- **Initial Setup:** Create admin account on first access

### NetBox - Network Documentation
- **URL:** http://192.168.2.50:8484
- **Username:** `admin`
- **Password:** `admin`
- **Database:**
  - User: `netbox`
  - Password: `netbox`

---

## 🌐 Networking Services

### Pi-Hole - DNS Ad Blocking
- **URL:** http://192.168.2.50:8088/admin
- **Password:** `pihole-admin-change-me`
- **DNS:** Port 53
- **Note:** Local network only (not exposed externally)

---

## 🔐 Security Recommendations

1. **Change ALL default passwords** immediately after first deployment
2. **Use strong, unique passwords** for each service (use a password manager!)
3. **Enable 2FA** where available (Vaultwarden, GitLab, etc.)
4. **Restrict external access** to only necessary services via Cloudflare Tunnel
5. **Keep local-only services** (Cockpit, Netdata, WUD, Pi-Hole) behind the firewall
6. **Regular backups** using Duplicati
7. **Monitor updates** with What's Up Docker (WUD)

---

## 📝 Notes

- **Default HOST_IP:** `192.168.2.50` (change in `.env`)
- **Database passwords** are for internal container-to-container communication
- **"Initial Setup"** means the service creates accounts on first web access
- **Local-only services** are not exposed via Cloudflare Tunnel for security
- **HTTPS-required services** (GitLab, Vaultwarden) only work via Cloudflare Tunnel
- **GPU services** (Stable Diffusion, ComfyUI, DiffRhythm) require NVIDIA GPU with drivers

---

## 🔗 Quick Access Summary

| Service | URL | Default Login |
|---------|-----|---------------|
| **Glance** | http://192.168.2.50:8098 | No auth |
| **Coder** | http://192.168.2.50:7080 | Create on first access |
| **Gitea** | http://192.168.2.50:7001 | Create on first access |
| **GitLab** | http://192.168.2.50:8929 | `root` / see container |
| **Open WebUI** | http://192.168.2.50:3000 | Create on first access |
| **SearXNG** | http://192.168.2.50:4000 | `searx` / `searxng-password-change-me` |
| **n8n** | http://192.168.2.50:5678 | Create on first access |
| **Paperless** | http://192.168.2.50:8082 | `admin` / `secure_paperless_password_change_me` |
| **NocoDB** | http://192.168.2.50:8090 | Create on first access |
| **Activepieces** | http://192.168.2.50:8087 | Create on first access |
| **Postiz** | http://192.168.2.50:8095 | `admin@example.com` / `secure_postiz_password_change_me` |
| **File Browser** | http://192.168.2.50:8096 | `admin` / `admin` |
| **Home Assistant** | http://192.168.2.50:8123 | Create on first access |
| **Node-RED** | http://192.168.2.50:1880 | No auth |
| **Immich** | http://192.168.2.50:2283 | Create on first access |
| **Kavita** | http://192.168.2.50:5000 | Create on first access |
| **Navidrome** | http://192.168.2.50:4533 | Create on first access |
| **Mealie** | http://192.168.2.50:9925 | Create on first access |
| **Firefly III** | http://192.168.2.50:8086 | Create on first access |
| **wger** | http://192.168.2.50:8089 | Create on first access |
| **Cockpit** | http://192.168.2.50:9090 | System user |
| **Dozzle** | http://192.168.2.50:9999 | No auth |
| **WUD** | http://192.168.2.50:3002 | `admin` / `admin` |
| **Uptime Kuma** | http://192.168.2.50:3001 | Create on first access |
| **Portainer** | http://192.168.2.50:9000 | Create on first access |
| **NetBox** | http://192.168.2.50:8484 | `admin` / `admin` |
| **Pi-Hole** | http://192.168.2.50:8088/admin | Password: `pihole-admin-change-me` |
