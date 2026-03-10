# Default Credentials Reference

## Traefik Authentication (External Access)

All services without built-in authentication use a shared default credential for external access via `*.weekendcodeproject.dev`:

**Username:** `admin`  
**Password:** `CHANGEME1234`

### Services Using Default Auth

These services require the default Traefik credentials when accessed externally:

- **Glance Dashboard** - home.weekendcodeproject.dev
- **IT-Tools** - it-tools.weekendcodeproject.dev  
- **Excalidraw** - excalidraw.weekendcodeproject.dev
- **LocalAI** - localai.weekendcodeproject.dev
- **AnythingLLM** - anythingllm.weekendcodeproject.dev
- **Whisper** - whisper.weekendcodeproject.dev
- **SearXNG** - searxng.weekendcodeproject.dev (username: `searx`, same password)

### Local Access (No Authentication)

When accessing services via `*.lab` domain on your local network, **no authentication is required** (trusted network pattern).

### Changing the Default Password

1. Update `DEFAULT_TRAEFIK_AUTH_PASS` in your `.env` file
2. Generate new bcrypt hash:
   ```bash
   docker run --rm httpd:alpine htpasswd -nbB admin YOUR_NEW_PASSWORD
   ```
3. Update auth files in `config/traefik/auth/` with the new hash (remember to escape `$` as `$$` in YAML)
4. Restart Traefik:
   ```bash
   docker compose restart traefik
   ```

## Configuration in .env

Add these variables to your `.env` file (already included in System Configuration section):

```bash
# Default Traefik Authentication
# Used for external access to services without built-in auth
DEFAULT_TRAEFIK_AUTH_USER=admin
DEFAULT_TRAEFIK_AUTH_PASS=CHANGEME1234
``` & Access Guide

> **⚠️ IMPORTANT:** These are the default credentials from `.env.example`. **Change all passwords in production!**

This document lists all default login credentials and access URLs for WeekendStack services using the default `HOST_IP=192.168.2.50` configuration.

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

##  Monitoring Services

### Dozzle - Docker Logs
- **URL:** http://192.168.2.50:9999
- **Auth:** None (read-only log viewer)

### What's Up Docker (WUD) - Update Manager
- **URL:** http://192.168.2.50:3002
- **Username:** `admin`
- **Password:** `admin`
- **Note:** Configure built-in auth via `WUD_AUTH_USER`/`WUD_AUTH_HASH` in `.env`

### Uptime Kuma - Service Monitoring
- **URL:** http://192.168.2.50:3001
- **Initial Setup:** Create admin account on first access

### Portainer - Container Management
- **URL:** http://192.168.2.50:9000 (HTTP) or https://192.168.2.50:9443 (HTTPS)
- **Initial Setup:** Create admin account on first access

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
3. **Enable 2FA** where available (Vaultwarden, Gitea, etc.)
4. **Restrict external access** to only necessary services via Cloudflare Tunnel
5. **Keep local-only services** (Pi-Hole, Dozzle) behind the firewall
6. **Monitor updates** with What's Up Docker (WUD)

---

## 📝 Notes

- **Default HOST_IP:** `192.168.2.50` (change in `.env`)
- **Database passwords** are for internal container-to-container communication
- **"Initial Setup"** means the service creates accounts on first web access
- **Local-only services** are not exposed via Cloudflare Tunnel for security
- **HTTPS-required services** (Vaultwarden) only work via Cloudflare Tunnel
- **GPU services** (Stable Diffusion, ComfyUI, DiffRhythm) require NVIDIA GPU with drivers

---

## 🔗 Quick Access Summary

| Service | URL | Default Login |
|---------|-----|---------------|
| **Glance** | http://192.168.2.50:8098 | No auth |
| **Coder** | http://192.168.2.50:7080 | Create on first access |
| **Gitea** | http://192.168.2.50:7001 | Create on first access |
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
| **Dozzle** | http://192.168.2.50:9999 | No auth |
| **WUD** | http://192.168.2.50:3002 | `admin` / `admin` |
| **Uptime Kuma** | http://192.168.2.50:3001 | Create on first access |
| **Portainer** | http://192.168.2.50:9000 | Create on first access |
| **Pi-Hole** | http://192.168.2.50:8088/admin | Password: `pihole-admin-change-me` |
