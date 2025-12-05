# wger Workout Manager Setup Guide

wger is a self-hosted fitness and workout manager.

## Quick Start

```bash
docker compose --profile personal up -d wger wger-nginx
```

**Note:** Both containers are required. The nginx sidecar serves static files (CSS/JS).

## Access

- **Local:** http://192.168.2.50:8089
- **External:** https://wger.weekendcodeproject.dev

## Default Credentials

- **Username:** admin
- **Password:** adminadmin

**Important:** Change the default password immediately after first login!

## Environment Variables

```env
WGER_PORT=8089
WGER_DOMAIN=wger.${BASE_DOMAIN}
WGER_MEMORY_LIMIT=512m

# Email settings (optional)
WGER_EMAIL_HOST=smtp.example.com
WGER_EMAIL_PORT=587
WGER_EMAIL_USER=your-email@example.com
WGER_EMAIL_PASSWORD=your-password
```

## Architecture

wger requires two containers:
1. **wger:** Main Django application (port 8000 internal)
2. **wger-nginx:** Nginx sidecar serving static files (CSS, JavaScript, images)

The nginx container serves `/static/` and `/media/` paths and proxies everything else to the wger app.

## Features

- Workout plan creation and tracking
- Exercise database with images
- Nutrition tracking and meal plans
- Weight and body measurement tracking
- Workout schedule calendar
- REST API for integrations

## Data Storage

- Database: SQLite (stored in wger-data volume)
- Static files: wger-static volume
- Media files: wger-media volume

## First-Time Setup

1. Log in with default credentials
2. Change admin password (Settings → Change Password)
3. Create your first workout plan
4. Add exercises from the database or create custom ones

## Syncing Exercise Database

To get the full exercise database with images:

```bash
docker exec wger python3 manage.py sync-exercises
docker exec wger python3 manage.py download-exercise-images
```

## Troubleshooting

### CSS/Styles Not Loading

Ensure the nginx sidecar is running:
```bash
docker compose ps wger-nginx
```

The nginx container must share the static/media volumes with wger.

### Permission Issues

The containers run with specific user permissions. If you see permission errors:
```bash
docker exec wger python3 manage.py collectstatic --no-input
```
