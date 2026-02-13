# 🏠 Weekend Stack

A comprehensive self-hosted Docker stack for development, AI, productivity, media, home automation, and monitoring. Features **65+ services** organized into modular compose files with profile-based deployment.

## ⚡ Quick Start (Automated Setup)

**New users:** Use our interactive setup script for a guided installation:

```bash
./setup.sh
```

This will:
- ✅ Check prerequisites (Docker, disk space, memory)
- ✅ Guide you through profile selection (AI, Dev, Productivity, etc.)
- ✅ Generate secure credentials automatically
- ✅ Create necessary directories with correct permissions
- ✅ Set up local HTTPS certificates
- ✅ Optionally configure Cloudflare Tunnel for external access
- ✅ Pull and start services

**Quick mode (with defaults):**
```bash
./setup.sh --quick
```

**For detailed instructions, see** [docs/setup-script-guide.md](docs/setup-script-guide.md)

---

## 📖 Manual Setup (Alternative)

If you prefer manual setup or need more control:

### 1. Authenticate with Docker Hub (Recommended)

To avoid rate limits when pulling images, authenticate with your Docker Hub account:

```bash
docker login -u your-username
```

When prompted for password, enter your **Personal Access Token (PAT)**, NOT your account password.

**Create a Personal Access Token:**
1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name it (e.g., "weekend-stack")
4. Select "Read, Write, Delete" permissions (or just "Read" for pull-only)
5. Click "Generate" and copy the token
6. Use this token as your password when running `docker login`

**Why authenticate?**
- Anonymous users: 100 pulls per 6 hours
- Authenticated free accounts: 200 pulls per 6 hours
- Required for pulling all AI service images without hitting rate limits

### 2. Clone and Configure

```bash
cd /opt/stacks/weekendstack
cp .env.example .env
# Edit .env with your settings
nano .env
```

### 3. Start Services

```bash
# Start all services
docker compose --profile all up -d

# Or start specific profiles
docker compose --profile ai up -d        # AI services only
docker compose --profile gpu up -d       # GPU-accelerated services only
docker compose --profile dev up -d       # Development services only
```

---

## 📦 Stack Overview

### Service Categories

| Category | Count | Description |
|----------|-------|-------------|
| **AI & ML** | 11 | LLM interfaces, search, image/music generation, speech processing |
| **Development** | 5 | Code servers, Git hosting, developer tools |
| **Productivity** | 11 | Document management, automation, collaboration |
| **Media** | 3 | Photo, music, and ebook management |
| **Personal** | 3 | Finance, recipes, fitness tracking |
| **Monitoring** | 7 | Container logs, metrics, uptime monitoring, server admin |
| **Networking** | 5 | Reverse proxy, custom error pages, DNS, tunneling |
| **Automation** | 2 | Home automation and flow-based programming |

---

## 🤖 AI & Machine Learning Services

| Service | Port | Description |
|---------|------|-------------|
| **Open WebUI** | 7005 | Chat interface for LLMs (connects to native Ollama) |
| **LibreChat** | 3080 | Multi-provider AI chat interface |
| **AnythingLLM** | 3001 | Desktop-style LLM workspace |
| **LocalAI** | 8080 | Local AI model server (OpenAI-compatible API) |
| **PrivateGPT** | 8001 | Private document Q&A with local models |
| **SearXNG** | 7009 | Privacy-focused metasearch engine (🔒 auth required) |
| **Stable Diffusion WebUI** | 7860 | AI image generation (requires NVIDIA GPU) |
| **ComfyUI** | 8188 | Node-based image generation workflow |
| **DiffRhythm** | 7870 | AI music generation from lyrics (requires NVIDIA GPU) |
| **Whisper** | 9000 | Speech-to-text transcription API |
| **WhisperX** | 9001 | Advanced speech recognition with alignment |

## 💻 Development Services

| Service | Port | Description |
|---------|------|-------------|
| **Coder** | 7080 | Cloud development environments (VS Code in browser) |
| **Gitea** | 7000 (HTTP), 7001 (SSH) | Lightweight Git hosting with Actions |
| **GitLab** | 7002 (HTTP), 7003 (SSH) | Full-featured DevOps platform |
| **ByteStash** | 5010 | Code snippet manager |
| **IT-Tools** | 8082 | Developer utilities collection (🔒 auth on public) |

## 📋 Productivity Services

| Service | Port | Description |
|---------|------|-------------|
| **Paperless-ngx** | 7010 | Document management with AI-powered OCR |
| **NocoDB** | 7011 | No-code database (Airtable alternative) |
| **n8n** | 7012 | Workflow automation platform |
| **Activepieces** | 7013 | Workflow automation (Zapier alternative) |
| **Vikunja** | 3456 | Task & project management (Todoist alternative) |
| **Trilium** | 8084 | Hierarchical note-taking with scripting |
| **Focalboard** | 8000 | Project boards (Trello/Notion alternative) |
| **Docmost** | 3003 | Collaborative documentation wiki |
| **Excalidraw** | 3002 | Collaborative whiteboard drawing |
| **Postiz** | 5001 | Social media scheduling & management |
| **Vaultwarden** | 8081 | Password manager (Bitwarden-compatible) |

## 🎬 Media Services

| Service | Port | Description |
|---------|------|-------------|
| **Immich** | 2283 | Photo & video backup (Google Photos alternative) |
| **Navidrome** | 4533 | Music streaming server (Subsonic-compatible) |
| **Kavita** | 5000 | Ebook, comic, and manga reader |

## 👤 Personal Services

| Service | Port | Description |
|---------|------|-------------|
| **Firefly III** | 8085 | Personal finance manager |
| **Mealie** | 9090 | Recipe manager & meal planner |
| **wger** | 8086 | Workout & fitness tracker |

## 📊 Monitoring Services

| Service | Port | Description |
|---------|------|-------------|
| **Cockpit** | 9090 | Local-only server administration UI (🔒 local network only) |
| **Portainer** | 9000 (HTTP), 9443 (HTTPS) | Docker container management UI |
| **Dozzle** | 9999 | Real-time container log viewer |
| **What's Up Docker (WUD)** | 3000 | Docker update notifications (🔒 local network only) |
| **Netdata** | 19999 | Real-time system & container metrics (🔒 local network only) |
| **Uptime Kuma** | 3001 | Service uptime monitoring |
| **Duplicati** | 8200 | Backup solution for all services |

## 🌐 Networking & Infrastructure

| Service | Port | Description |
|---------|------|-------------|
| **Traefik** | 80, 443 | Reverse proxy with automatic SSL (dashboard via `http://traefik.lab/dashboard/`) |
| **Error Pages** | 8080 | Custom 404/error pages for Traefik (ghost theme) |
| **Pi-Hole** | 53 (DNS), 8088 (admin) | Network-wide ad blocking |
| **Cloudflare Tunnel** | - | Secure public HTTPS access (no port forwarding) |
| **Glance** | 8098 | YAML dashboard with widgets and smart links |
| **Docker Registry** | 5000 | Local container image cache |

## 🏠 Home Automation

| Service | Port | Description |
|---------|------|-------------|
| **Home Assistant** | 8123 | Home automation platform |
| **Node-RED** | 1880 | Flow-based automation programming |

---

## 🚀 Quick Start

### Prerequisites

- Docker 24+ and Docker Compose v2+
- 8GB+ RAM (16GB+ recommended for AI services)
- 100GB+ disk space (SSD recommended)
- NVIDIA GPU with drivers (optional, for image generation)

### 1. Clone and Configure

```bash
git clone https://github.com/weekend-code-project/weekendstack.git
cd weekendstack

# Copy example environment
cp .env.example .env

# Edit configuration (set passwords, domains, API keys)
nano .env
```

### 2. Configure DNS (Required)

**⚠️ Services won't be accessible via `.lab` domains until DNS is configured.**

Choose ONE method:
- **Router-Level** (Recommended): Configure your router to resolve `*.lab` to your server IP
- **Pi-hole**: Use the included Pi-hole service as your network DNS server
- **/etc/hosts**: Add individual entries for testing (not recommended for production)

**Quick setup:**
```bash
# For most users with UniFi/pfSense routers:
# Set router DHCP to hand out 192.168.2.50 as DNS server
# See detailed guide: docs/dns-setup-guide.md

# For testing only (manual hosts file):
echo "192.168.2.50 home.lab coder.lab gitlab.lab" | sudo tee -a /etc/hosts

# Verify DNS is working:
bash tools/diagnose_lab.sh
```

📖 **Full guide:** [docs/dns-setup-guide.md](docs/dns-setup-guide.md)

### 3. Configure File Paths (Optional)

**For network shares or custom storage locations:**

Services that manage user files (photos, music, documents, etc.) support configurable storage paths. This allows you to:
- Point to existing media libraries on NAS/Unraid servers
- Use network shares (NFS, SMB/CIFS) for storage
- Keep files on separate drives or partitions

**Quick configuration in `.env`:**
```bash
# Point Navidrome to Unraid music share
NAVIDROME_MUSIC_PATH=/mnt/unraid/music

# Use network storage for photos
IMMICH_UPLOAD_PATH=/mnt/nas/photos

# Configure Paperless document paths
PAPERLESS_MEDIA_PATH=/mnt/nas/documents/paperless
PAPERLESS_CONSUME_PATH=/mnt/scanner/inbox

# Change base directory for all file services
FILES_BASE_DIR=/mnt/nas/weekendstack
```

**Supported services:**
- **Navidrome** - `NAVIDROME_MUSIC_PATH` (music library)
- **Immich** - `IMMICH_UPLOAD_PATH` (photo/video storage)
- **Kavita** - `KAVITA_LIBRARY_PATH` (ebook/manga library)
- **Paperless** - `PAPERLESS_MEDIA_PATH`, `PAPERLESS_CONSUME_PATH`, `PAPERLESS_EXPORT_PATH`
- **Other services** - Use `FILES_BASE_DIR` as base path

📖 **Detailed guides:**
- [File Paths Quick Reference](docs/file-paths-reference.md) - All configurable paths
- [File Mounts Configuration Guide](docs/file-mounts-guide.md) - NFS/SMB setup instructions
- [Unraid Share Example](docs/unraid-share-example.md) - Step-by-step Unraid integration

### 4. Start Services

```bash
# Start the default stack (profile `all`)
# NOTE: personal services are opt-in (use `--profile personal`)
docker compose up -d

# Start by profile (for selective deployment)
docker compose --profile dev up -d           # Development tools only
docker compose --profile ai up -d            # AI services only
docker compose --profile productivity up -d  # Productivity apps only
docker compose --profile media up -d         # Media services only
docker compose --profile monitoring up -d    # Monitoring stack
docker compose --profile automation up -d    # Home automation
docker compose --profile networking up -d    # Network infrastructure

# Optional: secure public HTTPS access via Cloudflare Tunnel
docker compose --profile external up -d

# Combine profiles
docker compose --profile dev --profile ai up -d

# Opt-in: personal services
docker compose --profile personal up -d
```

#### Profile Reference
- The default profile is `all`. GPU services are opt-in via `--profile gpu`.
- Check [`docs/profile-matrix.md`](docs/profile-matrix.md) for a full service × profile table before adding new toggles like `dev-gitea` or `dev-gitlab`.
- Mix and match profiles for targeted stacks, e.g. `docker compose --profile dev --profile networking up -d` (Coder + Traefik) or `docker compose --profile productivity --profile personal up -d` (office + lifestyle).

### 5. Access Services

**After configuring DNS** (step 2), all services are accessible via `.lab` domains:

**Main Dashboards:**
- **Glance**: http://home.lab - Main dashboard / start page
- **Traefik**: http://traefik.lab/dashboard/ - Routing status
- **Portainer**: http://portainer.lab - Container management
- **Cockpit**: http://cockpit.lab - Server management (local only)

**Quick Access:**
- Development: http://coder.lab, http://gitlab.lab, http://gitea.lab
- Productivity: http://nextcloud.lab, http://vikunja.lab, http://paperless.lab
- AI: http://open-webui.lab, http://librechat.lab
- Media: http://immich.lab, http://navidrome.lab, http://kavita.lab

**Alternative Access Methods:**
- Direct IP: `http://HOST_IP:PORT` (e.g., http://192.168.2.50:7080)
- See [service tables](#-ai--machine-learning-services) for port numbers

**Notes:**
- `.lab` domains support both HTTP and HTTPS (see step 5 for HTTPS setup)
- Public HTTPS hostnames use `BASE_DOMAIN` (e.g., `coder.${BASE_DOMAIN}`)
- If DNS isn't working, see [docs/dns-setup-guide.md](docs/dns-setup-guide.md)

All services are accessible at `http://HOST_IP:PORT` (set `HOST_IP` in `.env`).

Local DNS (`*.lab`) works when the `networking` profile is running and your router/DHCP hands out Pi-hole as the DNS server. Pi-hole will generate a wildcard so `*.lab` resolves to `HOST_IP`.

Notes:
- `*.lab` is meant for **local HTTP access** (no TLS). If a `*.lab` hostname has no matching router (or the service is down), Traefik redirects to `http://glance.lab/`.
- Public HTTPS hostnames are controlled by `BASE_DOMAIN` (for example: `coder.${BASE_DOMAIN}`). Don’t use `coder.example.com` unless you’ve actually set `BASE_DOMAIN=example.com` and configured external DNS/tunnel for it.

**Dashboards:**
- **Glance**: http://glance.lab - Dashboard / start page
- **Traefik**: http://traefik.lab/dashboard/ - Routing status
- **Portainer**: http://HOST_IP:9000 - Container management
- **Cockpit**: http://cockpit.lab - Server management (local only)

Setup docs:
- [docs/dns-setup-guide.md](docs/dns-setup-guide.md) - **DNS configuration (required)**
- [docs/local-https-setup.md](docs/local-https-setup.md) - **Enable HTTPS for .lab domains**
- [docs/glance-setup.md](docs/glance-setup.md)
- [docs/go-links-setup.md](docs/go-links-setup.md)
- [docs/filebrowser-setup.md](docs/filebrowser-setup.md)
- [docs/hoarder-setup.md](docs/hoarder-setup.md)

### 6. Optional: Enable Local HTTPS

The stack includes automated certificate generation for secure local access:

```bash
# Generate certificates (runs automatically on first startup)
docker compose up cert-generator

# Trust the CA certificate (one-time, see docs)
sudo cp config/traefik/certs/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt
sudo update-ca-certificates

# Restart Traefik to load certificates
docker compose restart traefik
```

After trusting the CA, all `.lab` domains work with HTTPS:
- `https://coder.lab` ✅
- `https://glance.lab` ✅  
- `https://nocodb.lab` ✅

See [docs/local-https-setup.md](docs/local-https-setup.md) for detailed instructions including Firefox, Windows, and macOS setup.

---

## 🗂️ Project Structure

```
weekendstack/
├── docker-compose.yml           # Main orchestrator (includes all modules)
├── setup.sh                    # Interactive setup wizard
├── uninstall.sh                # Safe uninstall script
├── Makefile                    # Common commands (make help)
│
├── compose/                     # Modular compose files
│   ├── docker-compose.core.yml      # Core services (Coder, databases)
│   ├── docker-compose.ai.yml        # AI/ML services
│   ├── docker-compose.dev.yml       # Development tools (Gitea, GitLab)
│   ├── docker-compose.productivity.yml  # Productivity apps
│   ├── docker-compose.media.yml     # Media services
│   ├── docker-compose.personal.yml  # Personal apps
│   ├── docker-compose.networking.yml    # Network infrastructure
│   ├── docker-compose.automation.yml    # Home automation
│   └── docker-compose.monitoring.yml    # Monitoring stack
│
├── config/                      # Service configurations
│   ├── cloudflare/             # Tunnel configuration
│   ├── traefik/                # Reverse proxy
│   │   ├── config.yml          # Static config
│   │   └── auth/               # Basic auth files (gitignored)
│   └── coder/                  # Development templates
│
├── files/                       # Service data volumes
│   ├── n8n/
│   ├── nocodb/
│   ├── open-webui/
│   ├── paperless/
│   └── ...
│
├── docs/                        # Additional documentation
│   ├── architecture.md
│   ├── network-architecture.md
│   ├── traefik-setup.md
│   └── ...
│
└── .env                         # Environment configuration (not in git)
```

---

## 🔧 Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Server identification
COMPUTER_NAME=weekendpc
BASE_DOMAIN=yourdomain.com
HOST_IP=192.168.2.50

# Cloudflare Tunnel (for public access)
# See config/cloudflare/config.yml.example and run with: docker compose --profile external up -d

# Service passwords (change all defaults!)
CODER_ADMIN_PASSWORD=secure-password
GITEA_ADMIN_PASSWORD=secure-password
PAPERLESS_ADMIN_PASSWORD=secure-password
# ... see .env.example for all options
```

### Traefik Authentication

Services exposed publicly use basic auth. Auth files are stored in `config/traefik/auth/` (gitignored):

```bash
# Generate password hash
htpasswd -nb admin your-password > config/traefik/auth/hashed_password-servicename

# Create middleware file
cat > config/traefik/auth/dynamic-servicename.yaml << EOF
http:
  middlewares:
    servicename-auth:
      basicAuth:
        usersFile: /auth/hashed_password-servicename
EOF
```

### Public vs Local Access

| Access Type | Method | URL Pattern |
|-------------|--------|-------------|
| **Local** | Direct port | `http://192.168.2.50:PORT` |
| **Public** | Cloudflare Tunnel | `https://service.yourdomain.com` |

Public services are routed through Cloudflare Tunnel with Traefik handling SSL termination and authentication.

---

## 🏗️ Architecture

### Network Design

```
Internet
    │
    ▼
Cloudflare Tunnel ──────► Traefik (Reverse Proxy)
                               │
                               ▼
              ┌────────────────┼────────────────┐
              │                │                │
         shared-network   ai-network    productivity-network
              │                │                │
         ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
         │ Glance  │      │Open WebUI│     │Paperless │
         │ Coder   │      │LibreChat │     │ NocoDB   │
         │ Gitea   │      │ SearXNG  │     │   N8N    │
         └─────────┘      └──────────┘     └──────────┘
```

### Service Dependencies

Most services are self-contained with their own databases:
- **Paperless**: PostgreSQL + Redis
- **NocoDB**: PostgreSQL
- **n8n**: PostgreSQL
- **Gitea**: PostgreSQL
- **Coder**: PostgreSQL

Shared services:
- **Traefik**: Handles all HTTP/HTTPS routing
- **Glance**: Dashboard / start page
- **Cloudflare Tunnel**: Exposes selected services publicly

---

## 📡 Public Access Setup

### Cloudflare Tunnel Configuration

1. Create a tunnel in Cloudflare Zero Trust dashboard
2. Get your tunnel token
3. Configure in `.env`:
   ```bash
   CLOUDFLARE_TUNNEL_TOKEN=your-token
   ```
4. Configure routes in `config/cloudflare/config.yml`:
   ```yaml
   ingress:
     - hostname: coder.yourdomain.com
       service: http://traefik:80
     - hostname: chat.yourdomain.com
       service: http://traefik:80
     - service: http_status:404
   ```

---

## 🐛 Troubleshooting

### Service Won't Start

```bash
# Check service logs
docker compose logs service-name

# Check all service health
docker compose ps

# Verify compose configuration
docker compose config
```

### Port Conflicts

```bash
# Check what's using a port
sudo netstat -tulpn | grep :7080

# Or with ss
sudo ss -tulpn | grep :7080
```

### Permission Issues

```bash
# Fix ownership for bind-mounted directories
sudo chown -R $USER:$USER ./files ./config

# Services with specific UID requirements:
sudo chown -R 1000:1000 ./files/n8n           # n8n runs as UID 1000
sudo chown -R 1000:1000 ./files/paperless     # Paperless runs as UID 1000
```

### Database Issues

```bash
# Check database health (should show "healthy")
docker compose ps | grep -E "(db|redis|postgres)"

# View database logs
docker compose logs paperless-db
docker compose logs coder-database
```

### Traefik Routing Issues

```bash
# Check Traefik dashboard
open http://localhost:8083/dashboard/

# View Traefik logs
docker compose logs traefik

# Test service routing
curl -I http://localhost:80 -H "Host: service.yourdomain.com"
```

---

## 📊 Resource Requirements

### Minimum Specs
- **CPU**: 4 cores
- **RAM**: 8GB
- **Disk**: 50GB
- **OS**: Linux (Ubuntu 22.04+ recommended)

### Recommended Specs
- **CPU**: 8+ cores
- **RAM**: 32GB (for AI services)
- **Disk**: 500GB+ SSD
- **GPU**: NVIDIA RTX 3060+ (for image generation)

### Per-Service Memory Limits

| Service | Default Limit |
|---------|--------------|
| Databases | 512MB-1GB |
| Coder | 4GB |
| Paperless | 2GB |
| Open WebUI | 2GB |
| Stable Diffusion | 8GB+ (GPU VRAM) |
| LocalAI | 4GB+ |

---

## 🔄 Backup Strategy

### Duplicati (Built-in)
Access at http://HOST_IP:8200 to configure automated backups of:
- `/opt/stacks/weekendstack/files/` - All service data
- `/opt/stacks/weekendstack/config/` - Configuration files

### Manual Backup

```bash
# Stop services
docker compose down

# Backup data
tar -czvf weekendstack-backup-$(date +%Y%m%d).tar.gz files/ config/ .env

# Restart
docker compose up -d
```

---

## 📚 Additional Documentation

See `docs/` directory for detailed guides:
- [Architecture Overview](docs/architecture.md)
- [Network Architecture](docs/network-architecture.md)
- [Traefik Setup](docs/traefik-setup.md)
- [Coder Templates Guide](docs/coder-templates-guide.md)
- [AI Services Integration](docs/ai-services-integration.md)
- [Paperless Integration](docs/paperless-integration.md)
- [SSH Keys Setup](docs/ssh-keys-setup.md)

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-service`
3. Test changes locally: `docker compose config`
4. Update documentation (this README + relevant docs/)
5. Submit a pull request

---

## 📄 License

This project configuration is provided as-is for self-hosted deployments. Individual services maintain their own licenses - refer to each service's documentation for licensing details.

---

**Quick Links:**
- [Environment Template](.env.example)
- [Glance Dashboard](http://glance.lab)
- [Traefik Dashboard](http://traefik.lab/dashboard/)
- [Documentation](docs/)
