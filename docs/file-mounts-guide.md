# File Mounts Configuration Guide

This guide explains how to configure external file storage for services that manage user files. All file paths are configurable via environment variables, making it easy to point to network shares, NFS mounts, or different local directories.

## Overview

Services that handle user files (photos, music, documents, etc.) support configurable storage paths through environment variables. This allows you to:

- Store files on network shares (NFS, SMB/CIFS)
- Keep files on separate drives or partitions
- Point to existing media libraries on other servers
- Share storage between multiple services or systems

## Supported Services

### Media Services

#### Immich - Photo & Video Management
**Environment Variable:** `IMMICH_UPLOAD_PATH`  
**Default:** `./files/immich/upload`  
**Container Path:** `/usr/src/app/upload`

Stores all uploaded photos and videos. Can point to large network storage for photo libraries.

```bash
# Example: Use network share
IMMICH_UPLOAD_PATH=/mnt/nfs/photos

# Example: Use separate drive
IMMICH_UPLOAD_PATH=/mnt/storage/immich
```

#### Navidrome - Music Streaming
**Environment Variable:** `NAVIDROME_MUSIC_PATH`  
**Default:** `./files/navidrome/music`  
**Container Path:** `/music` (read-only)

Music library directory. Perfect for pointing to existing music collections on NAS devices.

```bash
# Example: Point to Unraid music share
NAVIDROME_MUSIC_PATH=/mnt/unraid/music

# Example: Use NFS mount
NAVIDROME_MUSIC_PATH=/mnt/nfs/media/music
```

#### Kavita - eBook/Manga Reader
**Environment Variable:** `KAVITA_LIBRARY_PATH`  
**Default:** `./files/kavita/library`  
**Container Path:** `/manga`

Library directory for books, comics, and manga. Can point to existing ebook collections.

```bash
# Example: Point to calibre library
KAVITA_LIBRARY_PATH=/mnt/books/calibre-library

# Example: Use SMB share
KAVITA_LIBRARY_PATH=/mnt/smb/ebooks
```

### Productivity Services

#### Paperless-ngx - Document Management
**Environment Variables:**
- `PAPERLESS_MEDIA_PATH` - Stored/processed documents
- `PAPERLESS_CONSUME_PATH` - Inbox for new documents (watch folder)
- `PAPERLESS_EXPORT_PATH` - Export directory

**Defaults:**
- `${FILES_BASE_DIR}/paperless/media`
- `${FILES_BASE_DIR}/paperless/consume`
- `${FILES_BASE_DIR}/paperless/export`

**Container Paths:**
- `/usr/src/paperless/media`
- `/usr/src/paperless/consume`
- `/usr/src/paperless/export`

```bash
# Example: Use network storage
PAPERLESS_MEDIA_PATH=/mnt/nas/documents/paperless
PAPERLESS_CONSUME_PATH=/mnt/nas/scans/inbox
PAPERLESS_EXPORT_PATH=/mnt/nas/documents/exports

# Example: Use separate drives
PAPERLESS_MEDIA_PATH=/mnt/storage/paperless/media
PAPERLESS_CONSUME_PATH=/home/scanner/inbox
PAPERLESS_EXPORT_PATH=/mnt/backup/paperless-exports
```

#### Other Services Using FILES_BASE_DIR

The following services use paths relative to `FILES_BASE_DIR` (default: `./files`):

- **Postiz** - `${FILES_BASE_DIR}/postiz/uploads`
- **ResourceSpace** - `${FILES_BASE_DIR}/resourcespace`
- **Stable Diffusion** - `${FILES_BASE_DIR}/stable-diffusion/outputs`
- **DiffRhythm** - `${FILES_BASE_DIR}/diffrhythm/output` and `.../input`
- **FileBrowser** - `${FILES_BASE_DIR}` (entire files directory)

You can change the base directory for all these services:
```bash
# Change base directory to network share
FILES_BASE_DIR=/mnt/nas/weekendstack-files
```

## Network Share Setup

### NFS Mounts

1. Install NFS client:
```bash
sudo apt-get install nfs-common
```

2. Create mount point:
```bash
sudo mkdir -p /mnt/nfs/music
```

3. Mount NFS share:
```bash
sudo mount -t nfs 192.168.1.100:/volume1/music /mnt/nfs/music
```

4. Make permanent (add to `/etc/fstab`):
```
192.168.1.100:/volume1/music /mnt/nfs/music nfs defaults,auto,nofail 0 0
```

5. Update environment variable:
```bash
NAVIDROME_MUSIC_PATH=/mnt/nfs/music
```

### SMB/CIFS Mounts (Unraid, Windows Shares)

1. Install CIFS utilities:
```bash
sudo apt-get install cifs-utils
```

2. Create credentials file:
```bash
sudo mkdir -p /etc/smbcredentials
sudo nano /etc/smbcredentials/unraid
```

Add credentials:
```
username=your_username
password=your_password
```

Secure the file:
```bash
sudo chmod 600 /etc/smbcredentials/unraid
```

3. Create mount point:
```bash
sudo mkdir -p /mnt/unraid/music
```

4. Mount SMB share:
```bash
sudo mount -t cifs //192.168.1.100/music /mnt/unraid/music -o credentials=/etc/smbcredentials/unraid
```

5. Make permanent (add to `/etc/fstab`):
```
//192.168.1.100/music /mnt/unraid/music cifs credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000,file_mode=0755,dir_mode=0755,nofail 0 0
```

6. Update environment variable:
```bash
NAVIDROME_MUSIC_PATH=/mnt/unraid/music
```

## Configuration Examples

### Example 1: Music on Unraid, Photos on NAS

```bash
# .env file
NAVIDROME_MUSIC_PATH=/mnt/unraid/music
IMMICH_UPLOAD_PATH=/mnt/nas/photos
KAVITA_LIBRARY_PATH=/mnt/unraid/books
```

### Example 2: All files on network storage

```bash
# .env file
FILES_BASE_DIR=/mnt/nas/weekendstack
NAVIDROME_MUSIC_PATH=/mnt/nas/media/music
IMMICH_UPLOAD_PATH=/mnt/nas/photos/immich
KAVITA_LIBRARY_PATH=/mnt/nas/media/ebooks
PAPERLESS_MEDIA_PATH=/mnt/nas/documents/paperless
PAPERLESS_CONSUME_PATH=/mnt/scanner/inbox
```

### Example 3: Separate drives for different services

```bash
# .env file
NAVIDROME_MUSIC_PATH=/mnt/ssd/music
IMMICH_UPLOAD_PATH=/mnt/hdd/photos
PAPERLESS_MEDIA_PATH=/mnt/hdd/documents
FILES_BASE_DIR=/mnt/hdd/files
```

## Important Notes

### Permissions

Ensure the Docker user has proper permissions to access mounted directories:

```bash
# Option 1: Change ownership to match Docker user (typically 1000:1000)
sudo chown -R 1000:1000 /mnt/nfs/music

# Option 2: Use permissive mode (for read-only mounts like music)
sudo chmod -R 755 /mnt/nfs/music

# Option 3: Add user to specific group
sudo usermod -aG [group] docker
```

### Read-Only vs Read-Write

- **Navidrome** mounts music as read-only - it won't modify your files
- **Immich, Paperless, Kavita** need read-write access
- **Paperless consume** directory needs write access for document processing

### Performance Considerations

- **Local storage** provides best performance for databases and active processing
- **Network shares** work well for media files (music, photos, documents)
- **NFS** generally performs better than SMB/CIFS for Linux systems
- Consider using local SSD for service data/config, network storage for media files

### Backup Strategy

When using network shares:
1. Service **configuration** (Docker volumes) should still be backed up locally
2. Service **data** on network shares should be backed up according to your NAS/server backup strategy
3. Consider the `docker compose down` implications - network paths remain intact

## Applying Changes

After updating environment variables:

1. Edit `.env` file with new paths
2. Recreate affected services:
```bash
docker compose up -d navidrome immich-server paperless-ngx
```

3. Verify services can access the files:
```bash
docker compose logs navidrome
docker compose logs immich-server
```

## Troubleshooting

### Service can't see files

1. Check mount is active:
```bash
mount | grep /mnt/nfs
df -h /mnt/nfs/music
```

2. Check permissions:
```bash
ls -la /mnt/nfs/music
```

3. Check Docker can access:
```bash
docker compose exec navidrome ls -la /music
```

### Mount fails on boot

Add `nofail` option to `/etc/fstab` entries to prevent boot issues if network share is unavailable.

### Performance issues

- Check network bandwidth
- Consider local cache for frequently accessed files
- Use wired connection instead of WiFi for file server
- Verify NFS/SMB tuning parameters

## See Also

- [Services Guide](./services-guide.md) - Overview of all services
- [Deployment Guide](./deployment-guide.md) - General deployment information
- [Backup Strategy](./backup-strategy.md) - Service backup recommendations
