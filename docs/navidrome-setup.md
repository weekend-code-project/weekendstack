# Navidrome Setup Guide

Navidrome is a self-hosted music server compatible with Subsonic/Airsonic clients.

## Access URLs

| Type | URL |
|------|-----|
| Local | http://192.168.2.50:4533 |
| Public | https://music.weekendcodeproject.dev |

## Starting Navidrome

```bash
docker compose --profile media up -d navidrome
```

## Initial Setup

1. Navigate to http://192.168.2.50:4533
2. Create an admin account (first user becomes admin)
3. Navidrome will automatically scan the music folder

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAVIDROME_PORT` | 4533 | Host port for web UI |
| `NAVIDROME_DOMAIN` | music.${BASE_DOMAIN} | Domain for Traefik routing |
| `NAVIDROME_MUSIC_PATH` | ./files/navidrome/music | Host path for music files |
| `NAVIDROME_MEMORY_LIMIT` | 512m | Container memory limit |

## Storage Configuration

### Default: Local VM Storage

By default, Navidrome uses local VM storage at `./files/navidrome/music` for your music library.

### Advanced: NFS Network Storage

For large music libraries, you can configure Navidrome to use NFS storage (e.g., from Unraid NAS) instead of consuming VM disk space. This is ideal if you have a large existing music collection on a NAS.

#### Setup Steps

1. **Configure NFS Server** (e.g., Unraid)
   - Create NFS export (e.g., `/mnt/user/music` or `/mnt/user/navidrome-music`)
   - Set permissions: `192.168.2.0/24(sec=sys,rw,no_subtree_check,all_squash,anonuid=99,anongid=100)`

2. **Configure Environment Variables** in `.env`:
   ```bash
   NFS_SERVER_IP=192.168.2.3
   NFS_NAVIDROME_PATH=/mnt/user/music
   ```

3. **Edit docker-compose.media.yml**:
   - Uncomment the NFS volume definition at the bottom:
     ```yaml
     navidrome-nfs-music:
       driver: local
       driver_opts:
         type: nfs
         o: "addr=${NFS_SERVER_IP:-192.168.2.3},rw,nfsvers=4,nolock"
         device: ":${NFS_NAVIDROME_PATH:-/mnt/user/navidrome-music}"
     ```
   - In the navidrome service volumes section, comment out the bind mount and uncomment the NFS volume:
     ```yaml
     # - type: bind
     #   source: ${NAVIDROME_MUSIC_PATH:-./files/navidrome/music}
     #   target: /music
     #   read_only: true
     #   bind:
     #     create_host_path: true
     - type: volume
       source: navidrome-nfs-music
       target: /music
     ```

4. **Restart Navidrome**:
   ```bash
   docker compose down navidrome
   docker compose up -d navidrome
   ```

5. **Verify NFS Storage**:
   ```bash
   docker compose exec navidrome ls -la /music
   ```

#### Troubleshooting NFS

- **"Permission denied"**: Check NFS export has `rw` permissions and correct UID/GID mapping
- **"No such file or directory"**: Verify `NFS_NAVIDROME_PATH` matches your NFS export path
- **"Connection refused"**: Check firewall allows NFS traffic from Docker host

## Adding Music

Place your music files in the library folder:

```bash
# Default location
./files/navidrome/music/

# Recommended structure
./files/navidrome/music/
├── Artist Name/
│   ├── Album Name/
│   │   ├── 01 - Track Title.mp3
│   │   ├── 02 - Track Title.mp3
│   │   └── cover.jpg
│   └── Another Album/
│       └── ...
└── Another Artist/
    └── ...
```

### Supported Formats

- **Audio**: MP3, FLAC, AAC, OGG, WMA, WAV, AIFF, APE, WV, DSF, DFF
- **Playlists**: M3U, M3U8, PLS

## Features

- **Subsonic API**: Compatible with all Subsonic/Airsonic clients
- **Transcoding**: On-the-fly transcoding for bandwidth optimization
- **Smart Playlists**: Auto-generated playlists based on rules
- **Multi-user**: Separate libraries and settings per user
- **Last.fm Scrobbling**: Track listening history
- **ReplayGain**: Normalize playback volume
- **Lyrics**: Display synchronized lyrics

## Mobile Apps

Navidrome works with Subsonic-compatible apps:

### iOS
- **Substreamer** (recommended)
- **play:Sub**
- **Amperfy**

### Android
- **Subtracks** (recommended)
- **DSub**
- **Ultrasonic**

### Desktop
- **Sublime Music** (Linux)
- **Sonixd** (cross-platform)

## Connecting Apps

Use these settings in your Subsonic client:

| Setting | Value |
|---------|-------|
| Server URL | `http://192.168.2.50:4533` or `https://music.weekendcodeproject.dev` |
| Username | Your Navidrome username |
| Password | Your Navidrome password |

## Transcoding

Navidrome can transcode audio on-the-fly. Configure in **Settings** → **Transcoding**:

- **Max Bitrate**: Limit bandwidth usage
- **Format**: Convert to MP3/AAC/OPUS for compatibility

## Last.fm Scrobbling

1. Go to **Settings** → **Personal**
2. Click **Link Last.fm Account**
3. Authorize Navidrome

## Troubleshooting

### Music not appearing
```bash
# Check logs
docker logs navidrome --tail 50

# Force rescan (from web UI)
# Settings → Scan Music Library
```

### Check container status
```bash
docker ps --filter name=navidrome
```

### Restart Navidrome
```bash
docker compose --profile media restart navidrome
```
