# Monitoring Services Setup Guide

This guide covers the monitoring and container management services included in the `monitoring` profile. All services have their own login system and are safe for Cloudflare tunnel exposure.

## Services Overview

| Service | Port | Local Domain | Purpose |
|---------|------|-------------|---------|
| WUD | 3002 | `wud.lab` | Container update manager |
| Uptime Kuma | 3001 | `uptime-kuma.lab` | Service uptime monitoring |
| Portainer | 9000/9443 | `portainer.lab` | Docker container management |

## Quick Start

```bash
docker compose --profile monitoring up -d
```

---

## What's Up Docker (WUD)

Container update manager with a web dashboard. Shows available image updates — does NOT auto-apply them.

See [wud-setup.md](wud-setup.md) for detailed configuration.

### Access
- **Local:** http://192.168.2.50:3002

### Environment Variables
```env
WUD_PORT=3002
WUD_AUTH_USER=admin
WUD_AUTH_HASH=          # htpasswd -nbm USER PASS → copy hash after colon
```

### Authentication
WUD has built-in basic auth. Leave `WUD_AUTH_HASH` empty on first setup and set it after installation.

To generate a hash:
```bash
docker run --rm httpd:2-alpine htpasswd -nbm admin yourpassword
# Copy everything after the colon into WUD_AUTH_HASH
```

### How to Update Containers

1. Check WUD dashboard for available updates
2. Review changelogs for breaking changes
3. Pull and restart via docker compose:
```bash
docker compose pull <service-name>
docker compose up -d <service-name>
```

---

## Uptime Kuma

Self-hosted monitoring tool for tracking service uptime and alerting.

### Access
- **Local:** http://192.168.2.50:3001

### Environment Variables
```env
UPTIME_KUMA_PORT=3001
```

### First-Time Setup
1. Create admin account on first access
2. Add monitors for your services
3. Configure notification channels (Discord, Slack, email, etc.)

### Monitor Types
- **HTTP(S)** — Web endpoint monitoring
- **TCP Port** — Port availability
- **Ping** — ICMP ping
- **DNS** — DNS resolution
- **Docker** — Container health
- **Push** — Heartbeat monitoring

### Data Storage
SQLite database in the `uptime-kuma-data` volume.

---

## Portainer

Docker management UI for containers, images, networks, and volumes.

### Access
- **Local (HTTP):** http://192.168.2.50:9000
- **Local (HTTPS):** https://192.168.2.50:9443

### Environment Variables
```env
PORTAINER_PORT=9443
```

### First-Time Setup
1. Navigate to the web UI immediately after starting
2. Create your admin account (the setup page disables after 5 minutes)
3. Select "Local" environment to connect to the Docker socket

### Features
- Container management (start, stop, restart, logs)
- Image management and cleanup
- Network and volume management
- Stack deployment (docker compose via UI)
- User management

### Troubleshooting

**Socket Error:**
Ensure the Docker socket is mounted correctly:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

---

## Recommended Workflow

1. **Portainer** — Day-to-day container management and quick troubleshooting
2. **Uptime Kuma** — Add monitors for all public-facing services; set up alerts
3. **WUD** — Check weekly for available image updates; apply deliberately
