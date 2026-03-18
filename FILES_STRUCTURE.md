# WeekendStack Files Directory Structure

All user content is stored in the `files/` directory, making it easy to:
- Browse and manage through **Filebrowser** web UI (port 8096)
- Back up your content (single directory to backup)
- Use network storage (mount NFS/SMB to `files/` directory)

## Directory Structure

```
files/
├── immich/
│   └── upload/          # Photos and videos (uploaded via Immich mobile/web)
├── kavita/
│   └── library/         # eBooks, comics, manga
│       ├── Books/
│       ├── Comics/
│       └── Manga/
├── navidrome/
│   └── music/           # Music files (MP3, FLAC, etc.)
├── paperless/
│   ├── media/           # Stored documents
│   ├── consume/         # Auto-import inbox (drop files here)
│   └── export/          # Export directory
└── (other services...)
```

## Access Methods

### Via Filebrowser (Web UI)
- Access: http://${HOST_IP}:8096
- Login with the default admin credentials from setup
- Browse, upload, download, and manage all files through the web interface
- Supports drag-and-drop upload

### Via Terminal (SSH/Console)
```bash
cd /home/ubuntu/weekendstack/files/
ls -la immich/upload/     # View uploaded photos
ls -la kavita/library/    # View books/comics
ls -la navidrome/music/   # View music files
```

### Via SFTP/SCP
```bash
# Upload a book to Kavita
scp book.epub ubuntu@your-vm:/home/ubuntu/weekendstack/files/kavita/library/

# Upload music to Navidrome
scp -r MyAlbum/ ubuntu@your-vm:/home/ubuntu/weekendstack/files/navidrome/music/
```

## Media Services Configuration

### Immich (Photos & Videos)
- **Host Path:** `files/immich/upload/`
- **Container Path:** `/usr/src/app/upload`
- **Purpose:** Photo/video uploads from mobile app or web
- **Access:** Upload via Immich app; browse via Filebrowser

### Kavita (eBooks/Comics/Manga)
- **Host Path:** `files/kavita/library/`
- **Container Path:** `/manga` (inside Kavita container)
- **Purpose:** Digital library for reading content
- **Add Content:** 
  1. Upload files to `files/kavita/library/` via Filebrowser or SFTP
  2. In Kavita UI: Admin → Libraries → Scan Library
  3. When adding a library, use path `/manga`

### Navidrome (Music)
- **Host Path:** `files/navidrome/music/`
- **Container Path:** `/music` (inside Navidrome container)
- **Purpose:** Music streaming library
- **Add Content:**
  1. Upload music to `files/navidrome/music/` via Filebrowser or SFTP
  2. Navidrome auto-scans every hour (or trigger manual scan in UI)

### Paperless-ngx (Documents)
- **Media Path:** `files/paperless/media/` (stored documents)
- **Consume Path:** `files/paperless/consume/` (auto-import inbox)
- **Export Path:** `files/paperless/export/` (exports)
- **Add Content:**
  - Drop PDFs in `consume/` folder via Filebrowser
  - Paperless will auto-import and OCR them
  - Or upload directly via Paperless web UI

## Network Storage (Optional)

To use NFS or SMB shares instead of local storage:

### Option 1: Mount entire files directory
```bash
# Mount NFS share
sudo mount -t nfs 192.168.1.100:/mnt/user/weekendstack /home/ubuntu/weekendstack/files

# Add to /etc/fstab for persistence
192.168.1.100:/mnt/user/weekendstack /home/ubuntu/weekendstack/files nfs defaults 0 0
```

### Option 2: Per-service paths (via .env)
```bash
# .env
IMMICH_UPLOAD_PATH=/mnt/nas/photos
NAVIDROME_MUSIC_PATH=/mnt/nas/music
KAVITA_LIBRARY_PATH=/mnt/nas/books
PAPERLESS_MEDIA_PATH=/mnt/nas/documents/paperless/media
```

## Container Path Reference

When configuring libraries in service UIs:

| Service | Use This Path | Maps To |
|---------|---------------|---------|
| Kavita Library | `/manga` | `files/kavita/library/` |
| Navidrome Music | `/music` | `files/navidrome/music/` |
| Paperless Consume | `/usr/src/paperless/consume` | `files/paperless/consume/` |

## What Changed (March 2026)

- **Fixed:** Immich now uses `files/immich/upload/` by default (previously used NFS volume)
- **Confirmed:** Kavita, Navidrome, and Paperless already correctly use `files/` directory
- **Confirmed:** Filebrowser correctly mounts entire `files/` directory

All media services now follow the same pattern for consistency and ease of use.
