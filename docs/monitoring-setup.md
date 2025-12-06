# Monitoring Services Setup Guide

This guide covers the monitoring and infrastructure management services.

## Services Overview

| Service | Port | Purpose |
|---------|------|---------|
| Dozzle | 9999 | Real-time Docker log viewer |
| WUD | 3002 | Container update manager with dashboard |
| Uptime Kuma | 3001 | Status monitoring & alerting |
| Netdata | 19999 | System metrics & performance |
| Duplicati | 8200 | Backup solution |
| Portainer | 9000 | Docker management UI |

## Quick Start

```bash
docker compose --profile monitoring up -d
```

---

## Dozzle

Real-time Docker log viewer with filtering and search.

### Access
- **Local:** http://192.168.2.50:9999
- **External:** https://dozzle.weekendcodeproject.dev (Local access only)

### Environment Variables
```env
DOZZLE_PORT=9999
```

### Features
- Real-time log streaming
- Multi-container view
- Search and filter logs
- Log download
- Fuzzy search

### Security Note
Dozzle is configured for local access only and not exposed through Cloudflare tunnel.

---

## What's Up Docker (WUD)

Container update manager with a web dashboard. See [wud-setup.md](wud-setup.md) for detailed configuration.

### Access
- **Local:** http://192.168.2.50:3002
- **External:** https://wud.weekendcodeproject.dev

### Environment Variables
```env
WUD_PORT=3002
WUD_DOMAIN=wud.${BASE_DOMAIN}
```

### Features
- Visual dashboard showing all containers
- Shows available updates with version comparison
- Manual update triggers (you decide when to update)
- Notification support (Discord, Slack, Email, etc.)
- Does NOT auto-update by default

### How to Update Containers

1. Check WUD dashboard for available updates
2. Review changelogs for breaking changes
3. Update via docker compose:
```bash
docker compose pull <service-name>
docker compose up -d <service-name>
```

---

## Uptime Kuma

Self-hosted monitoring tool for tracking service uptime.

### Access
- **Local:** http://192.168.2.50:3001
- **External:** https://uptime.weekendcodeproject.dev

### Environment Variables
```env
UPTIME_KUMA_PORT=3001
UPTIME_KUMA_DOMAIN=uptime.${BASE_DOMAIN}
```

### First-Time Setup
1. Create admin account on first access
2. Add monitors for your services
3. Configure notification channels

### Monitor Types
- HTTP(S) - Web endpoint monitoring
- TCP Port - Port availability
- Ping - ICMP ping
- DNS - DNS resolution
- Docker - Container health
- Push - Heartbeat monitoring

### Data Storage
SQLite database in `uptime-kuma-data` volume.

---

## Netdata

Real-time system and application monitoring.

### Access
- **Local:** http://192.168.2.50:19999
- **External:** https://netdata.weekendcodeproject.dev

### Environment Variables
```env
NETDATA_PORT=19999
NETDATA_DOMAIN=netdata.${BASE_DOMAIN}
```

### Features
- Real-time system metrics (CPU, RAM, disk, network)
- Per-process resource usage
- Docker container metrics
- Anomaly detection
- Alerts and notifications
- Long-term metric storage

### Capabilities
The container runs with additional capabilities for system monitoring:
- `SYS_PTRACE` - Process monitoring
- Access to host `/proc`, `/sys`, `/etc/passwd`, `/etc/group`

---

## Duplicati

Web-based backup solution with encryption and cloud storage support.

### Access
- **Local:** http://192.168.2.50:8200
- **External:** https://duplicati.weekendcodeproject.dev

### Environment Variables
```env
DUPLICATI_PORT=8200
DUPLICATI_DOMAIN=duplicati.${BASE_DOMAIN}
DUPLICATI_DATA_PATH=${DATA_PATH}/duplicati

# Encryption (required)
SETTINGS_ENCRYPTION_KEY=<your-encryption-key>
```

### First-Time Setup
1. Access web interface
2. Create backup job
3. Select source folders
4. Configure destination (local, S3, Backblaze, etc.)
5. Set encryption passphrase
6. Schedule backups

### Backup Destinations
- Local folder
- SFTP/SSH
- Amazon S3
- Backblaze B2
- Google Drive
- Microsoft OneDrive
- Dropbox
- And many more...

### Source Directories
The container has access to:
- `/source` - Mapped to host `/opt` directory
- Configure backups to include your data directories

---

## Portainer

Docker management UI for containers, images, networks, and volumes.

### Access
- **Local:** http://192.168.2.50:9000
- **External:** https://portainer.weekendcodeproject.dev

### Environment Variables
```env
PORTAINER_PORT=9000
PORTAINER_DOMAIN=portainer.${BASE_DOMAIN}
```

### First-Time Setup
1. Create admin account (first 5 minutes after start)
2. Select "Local" environment
3. Connect to local Docker socket

### Features
- Container management (start, stop, restart, logs)
- Image management
- Network configuration
- Volume management
- Stack deployment
- User management
- Webhook support

### Security
Create your admin account immediately after first start. After 5 minutes, the setup page is disabled for security.

---

## Recommended Monitoring Setup

1. **Uptime Kuma:** Add monitors for all your public services
2. **Netdata:** Watch for resource constraints
3. **Dozzle:** Debug container issues via logs
4. **Portainer:** Quick container management
5. **Duplicati:** Scheduled backups of all data directories
6. **Watchtower:** Enable for non-critical services

## Data Directories

```
${DATA_PATH}/
├── duplicati/          # Duplicati config
└── other service dirs
```

## Troubleshooting

### Netdata High CPU
Normal during startup. If persistent, check `/etc/netdata/netdata.conf` settings.

### Duplicati Backup Failures
Check destination connectivity and disk space.

### Portainer Socket Error
Ensure Docker socket is mounted correctly:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```
