# WeekendStack Setup Script Guide

Complete guide to using the interactive setup script for automated WeekendStack deployment.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Setup Modes](#setup-modes)
- [Step-by-Step Walkthrough](#step-by-step-walkthrough)
- [Command-Line Options](#command-line-options)
- [Profile Selection Guide](#profile-selection-guide)
- [Configuration Options](#configuration-options)
- [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
- [Certificate Trust Setup](#certificate-trust-setup)
- [Troubleshooting](#troubleshooting)
- [Comparison with Manual Setup](#comparison-with-manual-setup)

---

## Overview

The WeekendStack setup script (`setup.sh`) provides an interactive, guided installation process that automates:

- **Environment configuration** with secure secret generation
- **Directory structure creation** with proper permissions
- **Docker authentication** for multiple registries
- **Service selection** via profile-based deployment
- **Certificate generation** for local HTTPS
- **Cloudflare Tunnel** configuration (optional)
- **Resource validation** to ensure system compatibility
- **Automated startup** with health checks

**Estimated time:** 5-15 minutes depending on options selected.

---

## Prerequisites

### Required

- **Docker** 24.0+ with Docker Compose V2
- **Linux** (Ubuntu, Debian, Fedora, Arch, or similar)
- **8GB+ RAM** (16GB+ recommended for full stack)
- **50GB+ disk space** (100GB+ for full stack with media)
- **Network connectivity** for image pulling

### Optional

- **NVIDIA GPU** with drivers + NVIDIA Container Toolkit (for GPU services)
- **Domain name** in Cloudflare (for Cloudflare Tunnel)
- **NFS server** (for network storage)

### Check Prerequisites

```bash
# Docker and Compose
docker --version
docker compose version

# Docker daemon running
docker info

# Disk space
df -h .

# Memory
free -h

# GPU (optional)
nvidia-smi
```

---

## Quick Start

### Interactive Mode (Recommended for First-Time Users)

```bash
./setup.sh
```

This will:
1. Show welcome screen and check prerequisites
2. Let you choose deployment profiles
3. Guide you through configuration (domains, credentials, paths)
4. Set up certificates and optionally Cloudflare Tunnel
5. Pull images and start services
6. Generate a comprehensive summary

### Quick Mode (Automated with Defaults)

```bash
./setup.sh --quick
```

Uses sensible defaults:
- Profile: Complete deployment (all services)
- Credentials: Auto-generated secure passwords
- Domains: `.lab` for local, `localhost` for external
- Paths: `./files`, `./data`, `./config`
- Skips: Docker authentication, Cloudflare setup

**Good for:** Testing, development environments, quick deployments

### Custom Quick Setup

```bash
# Quick setup without Cloudflare
./setup.sh --quick --skip-cloudflare

# Quick setup without certificate trust prompts
./setup.sh --quick --skip-certs

# Quick setup skipping image pull (use cached images)
./setup.sh --quick --skip-pull
```

---

## Setup Modes

### Interactive Mode

**Best for:** First-time users, production deployments, custom configurations

**Features:**
- Detailed prompts for all configuration
- Profile selection with service preview
- Custom domain and credential configuration
- Docker registry authentication wizard
- Cloudflare Tunnel setup wizard
- Certificate trust installation

**Usage:**
```bash
./setup.sh --interactive
# or simply
./setup.sh
```

### Quick Mode

**Best for:** Development, testing, automated deployments

**Features:**
- Auto-detected system settings (hostname, IP, timezone)
- Default profile selection
- Secure random password generation
- Minimal user interaction

**Usage:**
```bash
./setup.sh --quick
```

---

## Step-by-Step Walkthrough

### Step 1: Welcome and Prerequisites

The script will:
- Display welcome banner
- Check Docker installation and daemon status
- Verify available disk space and memory
- Detect NVIDIA GPU (if present)
- Estimate resource requirements

**Example output:**
```
=== Prerequisites Check ===
✓ Docker installed: v24.0.7
✓ Docker Compose installed: v2.23.0
✓ Docker daemon: running
✓ Disk space: 250GB available
✓ Memory: 32GB available
✓ NVIDIA GPU detected
```

### Step 2: Profile Selection

Choose which service categories to deploy:

**Quick Mode Options:**
1. Minimal - Core services only (3 services)
2. Developer - Core + Dev + AI (20+ services)
3. Productivity - Core + Productivity + Personal (40+ services)
4. Complete - All services (65+ services)
5. Custom - Choose specific profiles

**Interactive Mode:**
Use arrow keys and space bar to select profiles:
- `all` - Complete deployment (recommended)
- `core` - Essential services (Glance, Vaultwarden)
- `networking` - Traefik, Pi-hole, Cloudflare Tunnel
- `ai` - AI/LLM services (Ollama, Open WebUI, etc.)
- `dev` - Development tools (Coder, Gitea, GitLab)
- `productivity` - Business apps (Paperless, N8N, NocoDB)
- `personal` - Personal services (Immich, Mealie, Firefly)
- `media` - Media servers (Kavita, Navidrome)
- `monitoring` - Monitoring tools (Portainer, Uptime Kuma)
- `automation` - Home automation (Home Assistant)

**Resource check:** After selection, the script shows estimated requirements and validates available resources.

### Step 3: System Configuration

Configure basic system settings:

**Computer Name:**
```
Computer/host name [dev-workstation]: my-server
```

**Computer Type:**
```
Computer type:
  1) workstation
  2) server
  3) homelab
Select [1-3]: 3
```

**Host IP:**
```
Host IP address (for local DNS) [192.168.1.100]: 192.168.2.50
```

Auto-detected from network interfaces, but you can override.

**Timezone:**
```
Timezone [America/New_York]: America/Los_Angeles
```

**User/Group IDs:**
```
Current user: UID=1000 GID=1000
Use current user's UID/GID for file permissions? [Y/n]: y
```

### Step 4: Domain Configuration

**Local Domain** (for LAN access):
```
Local domain suffix (without dot) [lab]: home
```
Results in URLs like: `https://service.home`

**External Domain** (for Cloudflare Tunnel):
```
External domain [localhost]: example.com
```
- Leave as `localhost` if not using Cloudflare Tunnel
- Set to your domain if using Cloudflare

### Step 5: Admin Credentials

**Default credentials** for services that support auto-provisioning:

```
Set custom admin credentials now? [Y/n]: y
Admin username [admin]: admin
Admin email [admin@example.com]: admin@example.com
Set custom admin password? (or use generated random password) [y/N]: n
```

**Security note:** The script generates secure random passwords for:
- Database credentials (32-char hex)
- JWT secrets (64-char hex)
- Encryption keys (32-char hex)
- API tokens

### Step 6: File Path Configuration

```
Customize file storage locations? [y/N]: n
```

Default paths:
- User files: `./files` (documents, photos, media)
- Application data: `./data` (databases, caches)
- Configuration: `./config` (service configs)
- Workspaces: `/mnt/workspace` (Coder workspaces)

**Custom paths example:**
```
Customize file storage locations? [y/N]: y
User files directory [./files]: /mnt/nas/weekendstack/files
Application data directory [./data]: ./data
Configuration directory [./config]: ./config
Workspace directory [/mnt/workspace]: /home/ubuntu/workspaces
```

### Step 7: Docker Authentication

Authenticate with container registries to avoid rate limits:

```
=== Docker Registry Authentication ===

WeekendStack uses images from multiple registries:
  • Docker Hub (docker.io) - Most common images
  • GitHub Container Registry (ghcr.io) - Some services
  • Google Container Registry (gcr.io) - Optional services

Docker Hub credentials (for rate limit protection):
Docker Hub username []: myusername
Docker Hub password or token: ********
✓ Successfully authenticated with Docker Hub

Authenticate with GitHub Container Registry (ghcr.io)? [y/N]: n
```

**Skipped in quick mode** - Use `--interactive` for authentication.

### Step 8: Directory Creation

The script creates all necessary directories:
- Base directories (`config/`, `data/`, `files/`)
- Service-specific subdirectories
- Traefik auth directory (for workspace routing)
- SSH key directory

**SSH key generation** (if needed):
```
No SSH keys found in config/ssh
Generate new SSH key pair? [Y/n]: y
SSH key type:
  1) ed25519 (recommended)
  2) rsa 4096
Select [1-2]: 1
```

### Step 9: Certificate Generation

Generate self-signed CA and wildcard certificate:

```
=== Local HTTPS Certificate Generation ===

Generating self-signed CA and wildcard certificate for local HTTPS...
This enables https://service.lab access on your local network.

Running cert-generator init container...
✓ Certificates generated successfully

Install CA certificate for HTTPS trust? [Y/n]: y
```

See [Certificate Trust Setup](#certificate-trust-setup) section for OS-specific instructions.

### Step 10: Cloudflare Tunnel Setup (Optional)

Configure external access via Cloudflare Tunnel:

```
Set up Cloudflare Tunnel now? [Y/n]: y

Use cloudflared CLI for setup? [Y/n]: y
Domain name for tunnel []: example.com
Tunnel name [weekendstack-tunnel]: 

Authenticating with Cloudflare...
(Browser window opens for authentication)
✓ Authenticated with Cloudflare

Creating tunnel: weekendstack-tunnel
✓ Created tunnel: weekendstack-tunnel (ID: abc123...)
✓ Copied credentials to config/cloudflare/
✓ Created config: config/cloudflare/config.yml
✓ Created wildcard DNS record: *.example.com
```

See [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup) for detailed instructions.

### Step 11: Image Pulling

Pull Docker images for selected services:

```
=== Pulling Docker Images ===

This may take several minutes depending on your internet connection...

Pulling images for profiles: all
[+] Pulling 65/65
✓ All images pulled successfully
```

### Step 12: Init Containers

Run one-time initialization containers:

```
=== Running Init Containers ===

Running: cert-generator
✓ cert-generator completed successfully

Running: pihole-dnsmasq-init
✓ pihole-dnsmasq-init completed successfully

Running: coder-init
✓ coder-init completed successfully
```

### Step 13: Start Services

```
Start WeekendStack services now? [Y/n]: y

=== Starting Services ===

Starting services for profiles: all
[+] Running 65/65
✓ Services started successfully

Waiting for services to become healthy...

NAME                STATUS              PORTS
traefik            Up (healthy)        0.0.0.0:80->80/tcp, :::80->80/tcp
pihole             Up (healthy)        0.0.0.0:53->53/tcp
open-webui         Up                  0.0.0.0:7005->7005/tcp
...
```

### Step 14: Setup Complete

```
=== Setup Complete! ===

Quick Access:
  • Dashboard:    https://lab
  • Open WebUI:   https://open-webui.lab
  • Coder:        https://coder.lab
  • Portainer:    https://portainer.lab

Next Steps:
  1. Trust CA certificate (see SETUP_SUMMARY.md)
  2. Set DNS to Pi-hole (192.168.2.50)
  3. Create first user accounts on services
  4. Change default passwords!

Documentation:
  • Full summary: SETUP_SUMMARY.md
  • Guides:       docs/
  • Credentials:  docs/credentials-guide.md

✓ Your WeekendStack is ready to use!
```

---

## Command-Line Options

### General Options

```bash
-h, --help              # Show help message
-v, --version           # Show version
-q, --quick             # Quick setup with defaults
-i, --interactive       # Interactive setup (default)
--dry-run               # Show what would be done without executing
```

### Skip Options

```bash
--skip-auth             # Skip Docker registry authentication
--skip-pull             # Skip image pulling (use cached images)
--skip-cloudflare       # Skip Cloudflare Tunnel setup
--skip-certs            # Skip certificate generation
```

### Management Options

```bash
--validate              # Validate configuration without starting
--status                # Show current deployment status
--rollback              # Restore previous .env from backup
--start                 # Start the stack
--stop                  # Stop all services
--restart               # Restart all services
```

### Examples

```bash
# Quick setup without Cloudflare
./setup.sh --quick --skip-cloudflare

# Interactive with pre-existing Docker auth
./setup.sh --interactive --skip-auth

# Validate configuration
./setup.sh --validate

# Check deployment status
./setup.sh --status

# Start services (after setup)
./setup.sh --start

# Rollback to previous configuration
./setup.sh --rollback
```

---

## Profile Selection Guide

### Profile Descriptions

| Profile | Services | Memory | Disk | Use Case |
|---------|----------|--------|------|----------|
| **all** | 65+ | 48GB | 100GB | Complete self-hosted suite |
| **core** | 3 | 1GB | 5GB | Minimal dashboard + vault |
| **networking** | 6 | 2GB | 5GB | Reverse proxy, DNS, tunnel |
| **ai** | 11 | 16GB | 40GB | LLMs and AI tools |
| **dev** | 8 | 8GB | 20GB | Development environments |
| **productivity** | 24 | 12GB | 20GB | Business applications |
| **personal** | 7 | 6GB | 20GB | Finance, recipes, photos |
| **media** | 2 | 2GB | 10GB | eBooks, music |
| **monitoring** | 9 | 4GB | 10GB | Container management |
| **automation** | 3 | 2GB | 5GB | Home automation |

### Recommended Profile Combinations

**Developer Workstation:**
```bash
Profiles: core + networking + dev + ai
Total: ~30 services, 28GB RAM, 70GB disk
```

**Home Server:**
```bash
Profiles: core + networking + productivity + personal + media
Total: ~40 services, 22GB RAM, 60GB disk
```

**AI Research:**
```bash
Profiles: core + networking + ai + dev
Total: ~25 services, 26GB RAM, 65GB disk
```

**Minimal Testing:**
```bash
Profiles: core + networking
Total: ~9 services, 3GB RAM, 10GB disk
```

---

## Configuration Options

### Environment Variables

All configuration is stored in `.env` file. The setup script generates and customizes this file.

**Key sections:**
- System settings (hostname, timezone, IDs)
- Domain configuration (local and external)
- File paths (storage locations)
- Credentials (admin user, databases, secrets)
- Service-specific settings
- GPU configuration (if applicable)
- Cloudflare Tunnel settings

### Customization After Setup

Edit `.env` file:
```bash
nano .env
```

Apply changes:
```bash
docker compose down
docker compose up -d
```

Validate changes:
```bash
./tools/validate-env.sh
```

---

## Cloudflare Tunnel Setup

Two methods for Cloudflare Tunnel configuration:

### Method 1: CLI-Based (Automated)

Requirements:
- `cloudflared` CLI installed
- Cloudflare account
- Domain in Cloudflare

Steps (automated by script):
1. Authenticate with Cloudflare (browser)
2. Create tunnel with name
3. Generate credentials file
4. Create DNS record
5. Generate tunnel configuration

### Method 2: Manual (Web Dashboard)

Requirements:
- Cloudflare account
- Domain in Cloudflare

Steps:
1. Visit https://one.dash.cloudflare.com/
2. Navigate to Networks → Tunnels
3. Create tunnel (choose "Cloudflared")
4. Name tunnel (e.g., "weekendstack-tunnel")
5. Skip connector installation (using Docker)
6. Download credentials JSON
7. Copy to `config/cloudflare/` directory
8. Provide tunnel ID to setup script

The script will guide you through both methods.

### DNS Configuration

The tunnel requires a wildcard CNAME record:

```
Type:    CNAME
Name:    *
Target:  <tunnel-id>.cfargotunnel.com
Proxied: Yes (orange cloud)
```

**Automated:** Script creates this via API (CLI method)
**Manual:** Create in Cloudflare Dashboard

--- ## Certificate Trust Setup

To avoid browser security warnings, trust the generated CA certificate.

### Ubuntu/Debian

```bash
sudo cp config/traefik/certs/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt
sudo update-ca-certificates
```

### Fedora/RHEL/CentOS

```bash
sudo cp config/traefik/certs/ca-cert.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

### Arch Linux

```bash
sudo trust anchor --store config/traefik/certs/ca-cert.pem
```

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain config/traefik/certs/ca-cert.pem
```

### Windows (WSL)

Import via Windows Certificate Manager:
1. Open `certmgr.msc`
2. Right-click "Trusted Root Certification Authorities"
3. All Tasks → Import
4. Browse to `config/traefik/certs/ca-cert.pem`
5. Complete wizard

### Firefox (All Platforms)

Firefox uses its own certificate store:

1. Settings → Privacy & Security
2. View Certificates
3. Authorities → Import
4. Select `config/traefik/certs/ca-cert.pem`
5. Check "Trust for websites"

**Or use certutil (Linux):**
```bash
sudo apt install libnss3-tools
certutil -A -n "WeekendStack CA" -t "TCu,Cu,Tu" \
  -i config/traefik/certs/ca-cert.pem \
  -d "sql:$HOME/.mozilla/firefox/*.default"
```

---

## Troubleshooting

### Prerequisites Check Failures

**Docker not found:**
```
Install Docker: https://docs.docker.com/get-docker/
sudo systemctl start docker
sudo usermod -aG docker $USER
```

**Docker Compose not found:**
```
Ensure Docker Compose V2 is installed (part of Docker Desktop or Docker Engine)
Test: docker compose version
```

**Insufficient disk space:**
```
Free up space or use different partition
Consider reducing selected profiles
```

**Insufficient memory:**
```
Reduce selected profiles
Close other applications
Add swap space (not recommended for production)
```

### Configuration Issues

**.env validation fails:**
```
Run: ./tools/validate-env.sh
Fix reported issues
Re-run setup or manually edit .env
```

**Port conflicts:**
```
Check: docker compose ps
Stop conflicting services
Edit .env to change port numbers
```

### Network Issues

**Cannot resolve *.lab domains:**
```
1. Check Pi-hole is running: docker ps | grep pihole
2. Set DNS to HOST_IP in network settings
3. Test: nslookup service.lab
```

**Cloudflare Tunnel not working:**
```
1. Check logs: docker logs cloudflare-tunnel
2. Verify credentials file exists
3. Check DNS record in Cloudflare
4. Test: curl https://yourservice.example.com
```

### Certificate Issues

**Browser shows security warning:**
```
1. Trust CA certificate (see Certificate Trust Setup)
2. Restart browser
3. Check certificate validity: openssl x509 -in config/traefik/certs/cert.pem -text
```

### Service Startup Issues

**Service won't start:**
```
1. Check logs: docker compose logs <service>
2. Verify dependencies: docker compose ps
3. Check healthcheck: docker inspect <service>
4. Restart: docker compose restart <service>
```

**Database connection errors:**
```
1. Wait for database to be healthy
2. Check database logs
3. Verify credentials in .env
```

### Image Pull Failures

**Rate limit errors:**
```
Authenticate with Docker Hub: docker login
Wait for rate limit to reset (6 hours)
Use mirror/cache if available
```

**Network timeout:**
```
Check internet connection
Try again later
Use --skip-pull if images already cached
```

---

## Comparison with Manual Setup

| Aspect | Setup Script | Manual Setup |
|--------|--------------|---------------|
| **Time** | 5-15 minutes | 30-60 minutes |
| **Complexity** | Low (guided prompts) | High (read all docs) |
| **Error prone** | Low (validation built-in) | High (manual entry) |
| **Secret generation** | Automatic (secure random) | Manual (easy to forget) |
| **Directory creation** | Automatic | Manual |
| **Permissions** | Automatic (correct UID/GID) | Manual (errors common) |
| **Certificate setup** | Guided with OS detection | Manual (OS-specific) |
| **Cloudflare** | Wizard-guided | Fully manual |
| **Validation** | Built-in checks | Self-validation needed |
| **Documentation** | Auto-generated summary | None |
| **Rollback** | One command | Manual restore |

### When to Use Setup Script

- ✅ First-time deployment
- ✅ Production setup
- ✅ Time-sensitive deployment
- ✅ Unfamiliar with Docker Compose
- ✅ Want best practices enforced
- ✅ Need reproducible setup

### When to Use Manual Setup

- ✅ Advanced customization needed
- ✅ Partial deployment (few services)
- ✅ Troubleshooting/debugging
- ✅ Learning WeekendStack internals
- ✅ Air-gapped environment
- ✅ Custom automation integration

---

## Additional Resources

- **Setup summary:** `SETUP_SUMMARY.md` (generated after setup)
- **Service documentation:** `docs/<service>-setup.md`
- **Architecture:** `docs/architecture.md`
- **Credentials:** `docs/credentials-guide.md`
- **File paths:** `docs/file-paths-reference.md`
- **Troubleshooting:** `docs/deployment-guide.md`

---

**Questions or issues?** Check the generated `SETUP_SUMMARY.md` for your specific deployment details.
