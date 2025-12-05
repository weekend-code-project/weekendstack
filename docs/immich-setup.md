# Immich Setup

Immich is a self-hosted photo and video backup solution, similar to Google Photos.

## Configuration

Immich is configured in `docker-compose.media.yml` with the `media` profile.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMMICH_VERSION` | release | Image version tag |
| `IMMICH_PORT` | 2283 | Local HTTP port |
| `IMMICH_DOMAIN` | immich.${BASE_DOMAIN} | Public domain |
| `IMMICH_DB_USER` | immich | Database username |
| `IMMICH_DB_PASSWORD` | immich_password_2024 | Database password |
| `IMMICH_DB_NAME` | immich | Database name |
| `IMMICH_MEMORY_LIMIT` | 2g | Server memory limit |
| `IMMICH_ML_MEMORY_LIMIT` | 4g | ML service memory limit |

## Architecture

Immich consists of 4 containers:

| Container | Purpose |
|-----------|---------|
| `immich-server` | Main API and web server |
| `immich-ml` | Machine learning for face detection, object recognition |
| `immich-db` | PostgreSQL with pgvecto-rs for vector search |
| `immich-redis` | Cache and job queue |

## Starting Immich

```bash
docker compose --profile media up -d
```

This starts all Immich containers.

## Access

| Type | URL |
|------|-----|
| Local | http://192.168.2.50:2283 |
| Public | https://immich.weekendcodeproject.dev |

## First-Time Setup

1. Open Immich in your browser
2. Click "Getting Started"
3. Create the admin account (first user becomes admin)
4. Configure storage settings if needed
5. Download the mobile app (iOS/Android) to start backing up photos

## Mobile App Setup

1. Download "Immich" from App Store or Google Play
2. Open the app and enter your server URL:
   - Local: `http://192.168.2.50:2283`
   - Public: `https://immich.weekendcodeproject.dev`
3. Login with your admin credentials
4. Enable background backup

## Features

- **Automatic Backup** - Mobile apps backup photos/videos automatically
- **Face Recognition** - ML-powered face detection and grouping
- **Object Search** - Search photos by content ("dog", "beach", "car")
- **Location Map** - View photos on a world map
- **Memories** - "On this day" memories
- **Albums** - Organize photos into albums
- **Sharing** - Share albums with other users or public links
- **Timeline** - Chronological photo browsing

## Data Storage

Immich uses Docker volumes for data:

| Volume | Purpose |
|--------|---------|
| `immich-upload` | Photo and video uploads |
| `immich-model-cache` | ML model cache |
| `immich-db-data` | PostgreSQL database |
| `immich-redis-data` | Redis cache |

## Resource Requirements

- **RAM:** 4GB minimum (8GB+ recommended for ML features)
- **CPU:** 2+ cores (ML processing is CPU/GPU intensive)
- **Disk:** Depends on photo library size

## Troubleshooting

### Check Logs

```bash
# All Immich logs
docker logs immich-server
docker logs immich-ml
docker logs immich-db
docker logs immich-redis
```

### Health Check

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep immich
```

All containers should show `(healthy)` status.

### ML Processing Slow

The machine learning container downloads models on first run (~2GB). Initial face recognition and object detection can take time.

### Database Connection Issues

Ensure `immich-db` is healthy before `immich-server` starts:

```bash
docker logs immich-db
```

## Backup

### Database Backup

```bash
docker exec immich-db pg_dump -U immich immich > immich-db-backup.sql
```

### Full Backup (including uploads)

```bash
# Stop Immich first
docker compose --profile media stop

# Backup volumes
docker run --rm -v weekendstack_immich-upload:/data -v $(pwd):/backup alpine tar czf /backup/immich-upload.tar.gz /data
docker run --rm -v weekendstack_immich-db-data:/data -v $(pwd):/backup alpine tar czf /backup/immich-db.tar.gz /data

# Restart
docker compose --profile media up -d
```

## External Library (Optional)

To access photos from an existing folder without uploading:

1. Add a bind mount to `immich-server` in compose file
2. Configure External Library in Immich admin settings
3. Scan the library

## Updating Immich

```bash
docker compose --profile media pull
docker compose --profile media up -d
```

> ⚠️ Always check the [Immich release notes](https://github.com/immich-app/immich/releases) before updating. Some versions require database migrations.
