# Weekend Stack

A modular Docker Compose setup for running a complete self-hosted development and productivity environment with external domain access via Cloudflare Tunnel.

## 🚀 Quick Start

### 1. Prerequisites
- Docker and Docker Compose installed
- 8GB RAM minimum (16GB recommended)
- 50GB free disk space

### 2. Setup Environment
```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and customize:
# - COMPUTER_NAME: Used in service hostnames
# - BASE_DOMAIN: Your domain name
# - SSH_KEY_DIR: Absolute path to your ~/.ssh directory
# - Service passwords and secrets (search for "change-me")
```

### 3. Start the Stack
```bash
# Start all services with default profiles
docker compose up -d

# Or start specific profiles only
docker compose --profile ai up -d                    # AI services only
docker compose --profile productivity up -d          # Productivity services only
docker compose --profile all up -d                   # Everything (default)
```

### 4. Access Services

**Local Access (Direct Ports):**
- **Coder IDE**: http://localhost:7080
- **Gitea**: http://localhost:7001
- **Open WebUI**: http://localhost:3000
- **SearXNG**: http://localhost:4000 (requires auth)
- **Paperless**: http://localhost:8082
- **NocoDB**: http://localhost:8090
- **N8N**: http://localhost:5678
- **Traefik Dashboard**: http://localhost:8083/dashboard/
- **Pi-Hole**: http://localhost:8088/admin (internal only)

**External Access (via Cloudflare Tunnel):**
- https://coder.example.com
- https://gitea.example.com
- https://chat.example.com
- https://search.example.com
- https://paperless.example.com
- https://n8n.example.com

## 📦 Services Included

### Development & Infrastructure
- **Coder** - Cloud development environments
- **Gitea** - Self-hosted Git with Actions support
- **Docker Registry** - Container image cache
- **Traefik** - Reverse proxy and load balancer
- **Cloudflare Tunnel** - Secure external access

### Networking
- **Pi-Hole** - Network-wide ad blocking and DNS (internal only)

### AI Services
- **Open WebUI** - AI chat interface (connects to native Ollama)
- **SearXNG** - Privacy-focused meta search engine (with basic auth)
- **Stable Diffusion** - AI image generation (requires GPU, optional)

### Productivity
- **Paperless-ngx** - Document management with OCR
- **NocoDB** - Airtable alternative (spreadsheet-database hybrid)
- **N8N** - Workflow automation platform
- **Activepieces** - Alternative workflow automation

## 🏗️ Architecture

### Data Storage Strategy
- **Database State**: Docker-managed volumes (e.g., \`paperless-db-data\`, \`paperless-data\`)
- **Application Files**: Host bind mounts under \`./files/\` for user-facing content
- **Configuration**: \`./config/\` for service configs (Traefik auth, Cloudflare tunnel)

### Network Design
- **Isolated Networks**: Each service group has its own network
- **Shared Network**: Common network for inter-service communication
- **Traefik Integration**: All services route through Traefik for unified access

### Compose File Organization
```
docker-compose.yml              # Main file (includes all others)
├── docker-compose.core.yml     # Core infrastructure (databases)
├── docker-compose.networking.yml  # Traefik, Cloudflare Tunnel, Pi-Hole
├── docker-compose.dev.yml      # Coder, Gitea, Registry
├── docker-compose.ai.yml       # Open WebUI, SearXNG, Stable Diffusion
├── docker-compose.productivity.yml  # Paperless, NocoDB, N8N, Activepieces
└── docker-compose.override.yml # Local overrides (optional)
```

## ⚙️ Configuration

### Key Environment Variables

**Identity & Paths:**
```bash
COMPUTER_NAME=dev-workstation
BASE_DOMAIN=example.com
FILES_BASE_DIR=./files
CONFIG_BASE_DIR=./config
SSH_KEY_DIR=/home/yourusername/.ssh  # MUST be absolute path
```

**Service Control (via profiles):**
```bash
COMPOSE_PROFILES=all  # Options: all, ai, productivity, development, monitoring
```

**Security:**
- All services have configurable passwords in \`.env\`
- Traefik auth files stored in \`${CONFIG_BASE_DIR}/traefik/auth\`
- SearXNG protected with basic auth (username/password in \`.env\`)

## 🎯 Common Use Cases

### Development Workflow
1. **Coder**: Create cloud development environments with full IDE access
2. **Gitea**: Host Git repositories with Actions for CI/CD
3. **N8N**: Automate deployment and notification workflows

### Document Management
1. **Paperless-ngx**: Upload documents to \`./files/paperless/consume/\`
2. Documents are automatically OCR'd and indexed
3. Access via web UI or integrate with N8N for automation

### AI Integration
1. **Install Ollama natively** on your host (required - not containerized)
2. **Open WebUI** connects to \`http://host.docker.internal:11434\`
3. **SearXNG** provides privacy-focused search with basic auth protection

## 🔧 Service Management

### Start/Stop Services
```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# Restart a specific service
docker compose restart paperless-ngx

# View service logs
docker compose logs -f coder
docker compose logs -f traefik | grep searxng
```

### Profile Management
```bash
# Start only AI services
docker compose --profile ai up -d

# Start multiple profiles
docker compose --profile ai --profile productivity up -d

# Check what's running
docker compose ps
```

### Data Management
```bash
# Backup data (everything in ./files/ and Docker volumes)
tar -czf backup-$(date +%Y%m%d).tar.gz files/

# Reset a service (removes data!)
docker compose stop paperless-ngx paperless-db paperless-redis
docker volume rm wcp-coder_paperless-data wcp-coder_paperless-db-data
docker compose up -d paperless-ngx
```

## �� Security Configuration

### Traefik Basic Auth
Protected services use htpasswd-based authentication:

1. Auth files are in \`config/traefik/auth/\`
2. Create new auth with: \`htpasswd -nbB username password > config/traefik/auth/hashed_password-service\`
3. Create dynamic config: \`config/traefik/auth/dynamic-service.yaml\`
4. Add middleware label to service in compose file

**Example (SearXNG is already configured):**
```yaml
labels:
  - traefik.http.routers.searxng.middlewares=searxng-auth@file
```

### Cloudflare Tunnel Setup
1. Configure tunnel credentials in \`config/cloudflare/config.yml\`
2. Place credentials JSON in \`config/cloudflare/.cloudflared/\`
3. Set \`TUNNEL_NAME\` and \`TUNNEL_CREDENTIALS_FILE\` in \`.env\`

## 🐛 Troubleshooting

### Service Won't Start
```bash
# Check service logs
docker compose logs service-name

# Check if ports are in use
sudo netstat -tulpn | grep :7080

# Verify compose file syntax
docker compose config
```

### Permission Issues
```bash
# Fix ownership for bind-mounted directories
sudo chown -R $USER:$USER ./files ./config

# Specific services requiring specific UIDs:
# N8N runs as UID 1000
sudo chown -R 1000:1000 ./files/n8n
```

### Database Connection Issues
```bash
# Check database health
docker compose ps

# All database containers should show "(healthy)"
# If not, check logs:
docker compose logs paperless-db
docker compose logs coder-database
```

### Traefik Routing Issues
```bash
# Check Traefik dashboard
open http://localhost:8083/dashboard/

# View Traefik logs
docker compose logs traefik

# Verify service labels
docker compose config | grep -A 10 "service-name:"
```

### SearXNG Authentication
- **Issue**: Can't access SearXNG
- **Solution**: Check credentials in \`.env\`:
  ```bash
  SEARXNG_AUTH_USER=searx
  SEARXNG_AUTH_PASSWORD=your-password
  ```
- Auth file is at \`config/traefik/auth/hashed_password-searxng\`

## 📊 Resource Requirements

**Minimum:**
- CPU: 4 cores
- RAM: 8GB
- Disk: 50GB
- OS: Linux, macOS, Windows (WSL2)

**Recommended:**
- CPU: 8+ cores
- RAM: 16GB+
- Disk: 100GB+ (SSD recommended)

**Per-Service Limits (configurable in \`.env\`):**
- Databases: 512MB-1GB each
- Coder: 2GB
- Paperless: 2GB
- N8N: 2GB
- NocoDB: 2GB
- Open WebUI: 2GB
- Stable Diffusion: 6GB (GPU required)

## 🚢 Deployment Patterns

### Single Host (Development)
- Run everything on one machine
- Use default profiles (\`all\`)
- Access via localhost ports

### Multi-Host (Production)
- Split services across hosts by profile
- Use Traefik on dedicated proxy host
- Configure external domains

### GPU Workstation
- Enable \`gpu\` profile for Stable Diffusion
- Requires NVIDIA GPU with Docker runtime
- Configure via \`docker-compose.gpu.yml\`

## 📚 Additional Documentation

See \`docs/\` directory for:
- Architecture deep-dive
- Network configuration
- Service integration guides
- Migration and upgrade procedures

## 🤝 Contributing

Contributions welcome! Please:
1. Test changes locally with \`docker compose config\`
2. Update \`.env.example\` for new variables
3. Document changes in README
4. Keep commit messages clear

## 📄 License

This project configuration is provided as-is for self-hosted deployments. Individual services maintain their own licenses.

---

**Quick Links:**
- [Configuration Reference](.env.example)
- [Issue Tracker](https://github.com/weekend-code-project/weekendstack/issues)
- [Coder Templates](config/coder/templates/)
