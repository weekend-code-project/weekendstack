# File Path Quick Reference

Quick reference table for all configurable file storage paths. Edit these in your `.env` file to point to network shares, external drives, or custom locations.

## Media Services

| Service | Environment Variable | Default Path | Mount Point in Container | Access | Purpose |
|---------|---------------------|--------------|-------------------------|--------|----------|
| **Immich** | `IMMICH_UPLOAD_PATH` | `./files/immich/upload` | `/usr/src/app/upload` | Read-Write | Photo & video uploads |
| **Navidrome** | `NAVIDROME_MUSIC_PATH` | `./files/navidrome/music` | `/music` | Read-Only | Music library (MP3, FLAC, etc.) |
| **Kavita** | `KAVITA_LIBRARY_PATH` | `./files/kavita/library` | `/manga` | Read-Write | eBooks, comics, manga |

## Productivity Services

| Service | Environment Variable | Default Path | Mount Point in Container | Access | Purpose |
|---------|---------------------|--------------|-------------------------|--------|----------|
| **Paperless** | `PAPERLESS_MEDIA_PATH` | `${FILES_BASE_DIR}/paperless/media` | `/usr/src/paperless/media` | Read-Write | Processed documents |
| **Paperless** | `PAPERLESS_CONSUME_PATH` | `${FILES_BASE_DIR}/paperless/consume` | `/usr/src/paperless/consume` | Read-Write | Document inbox (watch folder) |
| **Paperless** | `PAPERLESS_EXPORT_PATH` | `${FILES_BASE_DIR}/paperless/export` | `/usr/src/paperless/export` | Read-Write | Export directory |

## AI Services

| Service | Environment Variable | Default Path | Mount Point in Container | Access | Purpose |
|---------|---------------------|--------------|-------------------------|--------|----------|
| **Stable Diffusion** | Uses `FILES_BASE_DIR` | `${FILES_BASE_DIR}/stable-diffusion/outputs` | `/outputs` | Read-Write | Generated images |
| **DiffRhythm** | Uses `FILES_BASE_DIR` | `${FILES_BASE_DIR}/diffrhythm/output` | `/app/output` | Read-Write | Output files |
| **DiffRhythm** | Uses `FILES_BASE_DIR` | `${FILES_BASE_DIR}/diffrhythm/input` | `/app/input` | Read-Write | Input files |

## Other Services

| Service | Environment Variable | Default Path | Mount Point in Container | Access | Purpose |
|---------|---------------------|--------------|-------------------------|--------|----------|
| **FileBrowser** | Uses `FILES_BASE_DIR` | `${FILES_BASE_DIR}` | `/srv` | Read-Write | Browse all files |
| **Postiz** | Uses `FILES_BASE_DIR` | `${FILES_BASE_DIR}/postiz/uploads` | `/uploads` | Read-Write | Social media uploads |
| **ResourceSpace** | Uses `FILES_BASE_DIR` | `${FILES_BASE_DIR}/resourcespace` | `/var/www/html/filestore` | Read-Write | Digital asset files |

## Base Directory

| Variable | Default | Purpose |
|----------|---------|---------|
| `FILES_BASE_DIR` | `./files` | Base directory for all file-based services. Change this to move all services to a new location. |

## Common Network Share Examples

### Point Navidrome to Unraid Music Share
```bash
NAVIDROME_MUSIC_PATH=/mnt/unraid/music
```

### Point Immich to NAS Photo Storage
```bash
IMMICH_UPLOAD_PATH=/mnt/nas/photos
```

### Move All Files to Network Storage
```bash
FILES_BASE_DIR=/mnt/nas/weekendstack
```

### Use Existing Library Locations
```bash
KAVITA_LIBRARY_PATH=/mnt/books/calibre-library
NAVIDROME_MUSIC_PATH=/mnt/media/music
PAPERLESS_MEDIA_PATH=/mnt/documents/archive
```

## After Making Changes

1. Edit `.env` file with new paths
2. Ensure mount points exist and have correct permissions
3. Recreate affected containers:
   ```bash
   docker compose up -d [service-name]
   ```

## See Full Guide

For detailed setup instructions including NFS/SMB configuration, see [File Mounts Configuration Guide](./file-mounts-guide.md).
