# Immich Setup

Immich is a self-hosted photo and video backup solution, similar to Google Photos.

## Configuration

Immich is configured in `docker-compose.personal.yml` with the `personal` profile.

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
docker compose --profile personal up -d
```

This starts all Immich containers (server, machine learning, database, and Redis cache).

To start with GPU acceleration for machine learning:

```bash
docker compose --profile personal --profile gpu-personal up -d
```

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

### Default: Local VM Storage

By default, Immich stores photos and videos on the VM's local filesystem at `./files/immich`.

### Advanced: NFS Network Storage

For large photo libraries, you can configure Immich to use NFS storage (e.g., from Unraid NAS) instead of consuming VM disk space. See the **NFS Storage Configuration** section below.

### Docker Volumes

Immich uses the following Docker volumes:

| Volume | Purpose |
|--------|---------|  
| `immich-nfs-uploads` (NFS) or bind mount (local) | Photo and video uploads |
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

## NFS Storage Configuration

For large photo libraries, using NFS storage (e.g., from Unraid NAS) prevents consuming VM disk space. Immich can store all uploads directly on network storage.

### Prerequisites

1. NFS server with a shared export (e.g., Unraid with `/mnt/user/photos` exported)
2. Network connectivity between Docker host and NFS server
3. Proper NFS export permissions configured on server

### Setup Steps

#### 1. Configure NFS Server (Unraid Example)

In Unraid, create an NFS export:

1. Go to Shares → Select or create a share (e.g., `photos`)
2. Enable **Export:** Yes
3. Set **Security:** Private  
4. Add rule: `192.168.2.0/24(sec=sys,rw,no_subtree_check,all_squash,anonuid=99,anongid=100)`
   - Adjust IP range to match your network
   - `all_squash` with `anonuid=99,anongid=100` maps all users to `nobody:users`

#### 2. Configure Environment Variables

Edit `.env` and add/uncomment:

```bash
# NFS Storage Configuration
NFS_SERVER_IP=192.168.2.3
NFS_PHOTOS_PATH=/mnt/user/photos/immich-uploads
```

Update the server IP and NFS path to match your NFS server.

#### 3. Create Required Folder Structure

Immich requires specific folders with marker files. Create them on the NFS share:

```bash
docker run --rm \
  -v weekendstack_immich-nfs-uploads:/upload \
  alpine sh -c '
    cd /upload && \
    mkdir -p upload library profile thumbs encoded-video backups && \
    touch upload/.immich library/.immich profile/.immich thumbs/.immich encoded-video/.immich backups/.immich && \
    ls -la && \
    ls -la upload/ library/ profile/ thumbs/ encoded-video/ backups/
  '
```

This command:
- Mounts the NFS volume
- Creates required subdirectories
- Creates `.immich` marker files in each directory
- Verifies the structure

#### 4. Start Immich

```bash
docker compose --profile personal up -d
```

#### 5. Verify NFS Storage

Check that Immich is using NFS storage:

```bash
# Check mount inside container
docker compose exec immich-server ls -la /usr/src/app/upload

# Should show uid=99 (nobody) ownership:
# drwxrwxr-x 7 99 users 4096 ... .
```

Upload a test photo through the Immich web UI, then verify it appears on the NFS server (e.g., check the Unraid share).

### How It Works

The `docker-compose.personal.yml` file defines an NFS volume:

```yaml
volumes:
  immich-nfs-uploads:
    driver: local
    driver_opts:
      type: nfs
      o: "addr=${NFS_SERVER_IP:-192.168.2.3},rw,nfsvers=4,nolock"
      device: ":${NFS_PHOTOS_PATH:-/mnt/user/photos/immich-uploads}"
```

This Docker volume:
- Uses the local driver with NFS backend
- Connects to the NFS server at `$NFS_SERVER_IP`
- Mounts the path `$NFS_PHOTOS_PATH`
- Uses NFSv4 protocol

The `immich-server` container mounts this volume at `/usr/src/app/upload`, so all photos/videos are stored directly on the NFS server.

### Switching Back to Local Storage

To switch from NFS back to local storage:

1. Comment out NFS variables in `.env`:
   ```bash
   # NFS_SERVER_IP=192.168.2.3
   # NFS_PHOTOS_PATH=/mnt/user/photos/immich-uploads
   ```

2. Update `IMMICH_UPLOAD_PATH` to use local storage:
   ```bash
   IMMICH_UPLOAD_PATH=./files/immich
   ```

3. Modify `docker-compose.personal.yml` to use a bind mount instead of the NFS volume (see git history for the original configuration)

4. Restart Immich:
   ```bash
   docker compose --profile personal down
   docker compose --profile personal up -d
   ```

### Troubleshooting NFS Storage

**Container fails to start with "invalid argument"**
- Check NFS server is accessible: `ping $NFS_SERVER_IP`
- Verify NFS export is configured: `showmount -e $NFS_SERVER_IP`
- Ensure NFS export path matches `NFS_PHOTOS_PATH`

**Permission denied errors**
- Verify NFS export has `rw` (read-write) permissions
- Check `anonuid=99,anongid=100` in NFS export rules
- Inspect volume: `docker volume inspect weekendstack_immich-nfs-uploads`

**Missing folder structure errors**
- Re-run the folder creation command from step 3
- Verify `.immich` marker files exist in each subdirectory

**Files not appearing on NFS server**
- Check volume mounting: `docker compose exec immich-server df -h`
- Verify upload path: `docker compose exec immich-server ls -la /usr/src/app/upload`
- Check NFS server logs for connection attempts

## Backup

### Database Backup

```bash
docker exec immich-db pg_dump -U immich immich > immich-db-backup.sql
```

### Full Backup (including uploads)

```bash
# Stop Immich first
docker compose --profile personal stop

# Backup volumes (adjust volume name based on your configuration)
docker run --rm -v weekendstack_immich-nfs-uploads:/data -v $(pwd):/backup alpine tar czf /backup/immich-uploads.tar.gz /data
docker run --rm -v weekendstack_immich-db-data:/data -v $(pwd):/backup alpine tar czf /backup/immich-db.tar.gz /data

# Restart
docker compose --profile personal up -d
```

**Note:** If using NFS storage, you can backup directly from the NFS server instead of using the Docker volume backup method.

## External Library (Optional)

To access photos from an existing folder without uploading:

1. Add a bind mount to `immich-server` in compose file
2. Configure External Library in Immich admin settings
3. Scan the library

## Updating Immich

```bash
docker compose --profile personal pull
docker compose --profile media up -d
```

> ⚠️ Always check the [Immich release notes](https://github.com/immich-app/immich/releases) before updating. Some versions require database migrations.
