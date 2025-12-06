# What's Up Docker (WUD) Setup Guide

What's Up Docker (WUD) is a container update manager with a web dashboard. Unlike Watchtower, WUD shows you available updates and lets you decide when to update.

## Quick Start

```bash
docker compose --profile monitoring up -d wud
```

## Access

- **Local:** http://192.168.2.50:3002
- **External:** https://wud.weekendcodeproject.dev

## Environment Variables

```env
WUD_PORT=3002
WUD_DOMAIN=wud.${BASE_DOMAIN}
WUD_MEMORY_LIMIT=256m
```

## How WUD Works

1. **Watches** - Monitors all running containers for available image updates
2. **Reports** - Shows which containers have newer versions available
3. **You Decide** - Does NOT auto-update by default; you review and trigger updates

## Dashboard Overview

The WUD dashboard shows:
- **Container Name** - The running container
- **Current Version** - Currently installed image tag
- **New Version** - Available update (if any)
- **Registry** - Where the image comes from (Docker Hub, GHCR, etc.)
- **Update Status** - Green checkmark (up to date) or orange indicator (update available)

## Checking for Updates

WUD automatically checks for updates based on the cron schedule (default: daily at midnight).

To manually trigger a check:
1. Open the WUD dashboard
2. Click the refresh icon in the top right
3. Wait for the scan to complete

## Performing Updates

### Method 1: Via WUD Triggers (Recommended for Single Containers)

WUD can trigger updates if you enable a trigger. Add to your `.env`:

```env
# Enable Docker trigger for WUD
WUD_TRIGGER_DOCKER_ENABLE=true
```

Then in the WUD dashboard, you can click "Update" on individual containers.

### Method 2: Via Docker Compose (Recommended for Stack Updates)

For more control, update containers via compose:

```bash
# Pull new images for all services
docker compose pull

# Recreate containers with new images
docker compose --profile all up -d

# Or update specific services
docker compose pull paperless-ngx
docker compose --profile productivity up -d paperless-ngx
```

### Method 3: Via Portainer

1. Open Portainer (http://192.168.2.50:9000)
2. Go to Containers
3. Select the container to update
4. Click "Recreate" with "Pull latest image" checked

## Configuration Options

### Change Check Schedule

Edit the cron schedule in `docker-compose.monitoring.yml`:

```yaml
environment:
  - WUD_WATCHER_LOCAL_CRON=0 0 * * *  # Default: midnight daily
  - WUD_WATCHER_LOCAL_CRON=0 */6 * * *  # Every 6 hours
  - WUD_WATCHER_LOCAL_CRON=0 0 * * 0  # Weekly on Sunday
```

### Watch Specific Containers Only

By default, WUD watches all containers. To watch only labeled containers:

```yaml
environment:
  - WUD_WATCHER_LOCAL_WATCHBYDEFAULT=false
```

Then add labels to containers you want monitored:

```yaml
labels:
  - "wud.watch=true"
```

### Exclude Containers

To exclude specific containers from monitoring:

```yaml
# On the container you want to exclude
labels:
  - "wud.watch=false"
```

### Enable Notifications

WUD supports various notification providers. Example for Discord:

```env
WUD_TRIGGER_DISCORD_ENABLE=true
WUD_TRIGGER_DISCORD_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
```

Other supported triggers:
- Slack
- Telegram  
- Email (SMTP)
- Pushover
- Apprise
- Custom webhooks

## Registry Authentication

For private registries, configure authentication:

```yaml
environment:
  # Docker Hub (for rate limit increase)
  - WUD_REGISTRY_HUB_LOGIN=your-username
  - WUD_REGISTRY_HUB_PASSWORD=your-password
  
  # GitHub Container Registry
  - WUD_REGISTRY_GHCR_LOGIN=your-github-username
  - WUD_REGISTRY_GHCR_PASSWORD=ghp_your_token
```

## Understanding Image Tags

WUD works best with semantic versioning tags:
- ✅ `nginx:1.25.3` - WUD can detect `1.25.4`, `1.26.0`, etc.
- ✅ `postgres:15` - WUD can detect `15.1`, `15.2`, etc.
- ⚠️ `nginx:latest` - WUD can only detect if the digest changed
- ⚠️ `myapp:dev` - Non-semantic tags are harder to track

## Best Practices

1. **Review before updating** - Check release notes for breaking changes
2. **Backup first** - Especially for databases and stateful services
3. **Update in batches** - Don't update everything at once
4. **Test critical services** - Verify functionality after updates
5. **Keep compose files versioned** - Pin versions for stability

## Recommended Update Workflow

1. **Check WUD dashboard** for available updates
2. **Review changelogs** for services with updates
3. **Backup data** for stateful services (databases, configs)
4. **Update non-critical services first** (monitoring, dashboards)
5. **Update critical services** one at a time
6. **Verify functionality** after each update

## Troubleshooting

### WUD Not Detecting Updates

- Check that the container is using a proper tag (not `latest` digest issues)
- Verify registry connectivity
- Check WUD logs: `docker logs wud`

### Rate Limited by Docker Hub

Add Docker Hub credentials to increase rate limits:
```env
WUD_REGISTRY_HUB_LOGIN=username
WUD_REGISTRY_HUB_PASSWORD=password
```

### Container Shows Wrong Version

WUD reads the image tag, not the application version. If a container uses `latest`, WUD tracks the digest hash instead.

## WUD vs Watchtower

| Feature | WUD | Watchtower |
|---------|-----|------------|
| Web Dashboard | ✅ Yes | ❌ No |
| Auto-Update | Optional | Default |
| Manual Review | ✅ Yes | ❌ No |
| Notifications | ✅ Yes | ✅ Yes |
| Version Comparison | ✅ Visual | Logs only |

WUD is better for production environments where you want to review updates before applying them.
