# Monitoring Services Setup Guide

This guide covers the monitoring services included in the `monitoring` profile.

## Services Overview

| Service | Port | Local Domain | Purpose |
|---------|------|-------------|---------|
| WUD | 3002 | `wud.lab` | Container update manager |
| Uptime Kuma | 3001 | `uptime-kuma.lab` | Service uptime monitoring |

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
WUD_WATCHER_LOCAL_CRON="0 0 * * *"
WUD_WATCHER_LOCAL_WATCHBYDEFAULT=true
WUD_TRIGGER_DOCKER_ENABLE=false
```

### Authentication
WUD built-in basic auth is disabled by default in this stack.
If you expose WUD externally, keep Traefik auth enabled on the route.

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

## Recommended Workflow

1. **Uptime Kuma** — Add monitors for all public-facing services; set up alerts
2. **WUD** — Check weekly for available image updates; apply deliberately
