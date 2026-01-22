# Example: Using Unraid Music Share with Navidrome

This example shows how to configure Navidrome to use an existing music library on an Unraid server.

## Scenario

- Unraid server IP: `192.168.1.100`
- Music share name: `music`
- Music path on Unraid: `/mnt/user/music/`
- Contains existing MP3/FLAC collection

## Step 1: Mount Unraid Share

On your Docker host, mount the Unraid share:

```bash
# Create mount point
sudo mkdir -p /mnt/unraid/music

# Install CIFS utilities if not already installed
sudo apt-get update && sudo apt-get install -y cifs-utils

# Create credentials file (optional but recommended)
sudo mkdir -p /etc/smbcredentials
sudo nano /etc/smbcredentials/unraid

# Add your Unraid credentials:
username=your_unraid_username
password=your_unraid_password

# Secure the credentials file
sudo chmod 600 /etc/smbcredentials/unraid

# Test mount
sudo mount -t cifs //192.168.1.100/music /mnt/unraid/music -o credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000

# Verify it worked
ls -la /mnt/unraid/music
```

## Step 2: Make Mount Permanent

Add to `/etc/fstab` so it mounts on boot:

```bash
sudo nano /etc/fstab
```

Add this line:
```
//192.168.1.100/music /mnt/unraid/music cifs credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000,file_mode=0755,dir_mode=0755,nofail,vers=3.0 0 0
```

Options explained:
- `credentials=` - Path to credentials file
- `uid=1000,gid=1000` - Match Docker user permissions
- `file_mode=0755` - Files readable by all, writable by owner
- `dir_mode=0755` - Directories readable/executable by all
- `nofail` - Don't fail boot if share unavailable
- `vers=3.0` - SMB protocol version (adjust if needed)

Test the fstab entry:
```bash
sudo mount -a
df -h | grep unraid
```

## Step 3: Update Environment Variable

Edit your `.env` file:

```bash
cd /opt/stacks/weekendstack
nano .env
```

Find the Navidrome section and update:
```bash
NAVIDROME_MUSIC_PATH=/mnt/unraid/music
```

## Step 4: Recreate Navidrome Container

```bash
docker compose up -d navidrome
```

## Step 5: Verify

Check Navidrome logs:
```bash
docker compose logs navidrome
```

You should see it scanning your music library.

Access Navidrome at `https://navidrome.lab` and verify your music appears.

## Troubleshooting

### Mount Not Working

Check if share is accessible:
```bash
smbclient -L //192.168.1.100 -U your_username
```

Try different SMB versions:
```bash
# Try SMB 2.0
sudo mount -t cifs //192.168.1.100/music /mnt/unraid/music -o credentials=/etc/smbcredentials/unraid,vers=2.0

# Try SMB 1.0 (legacy)
sudo mount -t cifs //192.168.1.100/music /mnt/unraid/music -o credentials=/etc/smbcredentials/unraid,vers=1.0
```

### Permission Issues

If Navidrome can't read files:
```bash
# Check current permissions
ls -la /mnt/unraid/music

# Remount with different UID/GID
sudo umount /mnt/unraid/music
sudo mount -t cifs //192.168.1.100/music /mnt/unraid/music -o credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000,file_mode=0644,dir_mode=0755
```

### Navidrome Not Seeing Files

Check what Navidrome sees:
```bash
docker compose exec navidrome ls -la /music
docker compose exec navidrome du -sh /music
```

Force rescan:
```bash
docker compose restart navidrome
```

### Mount Disappears After Reboot

Ensure `/etc/fstab` entry is correct and includes `nofail` option.

Check mount status:
```bash
systemctl status -.mount
mount | grep unraid
```

## Performance Tips

1. **Use Gigabit Ethernet** - Wireless can cause stuttering
2. **Enable SMB Multichannel** on Unraid (Settings → SMB)
3. **Adjust Cache Settings** in Navidrome if needed
4. **Use Transcoding** for mobile clients to reduce bandwidth

## Alternative: NFS Mount

If your Unraid server supports NFS (Settings → NFS), you can use NFS instead of SMB for better performance:

```bash
# Install NFS client
sudo apt-get install nfs-common

# Mount via NFS
sudo mount -t nfs 192.168.1.100:/mnt/user/music /mnt/unraid/music

# Add to /etc/fstab
192.168.1.100:/mnt/user/music /mnt/unraid/music nfs defaults,auto,nofail 0 0
```

NFS typically has better performance for Linux systems.

## Other Services on Unraid

You can use the same approach for other services:

### Kavita with Unraid Book Share
```bash
sudo mkdir -p /mnt/unraid/books
# Add to /etc/fstab:
//192.168.1.100/books /mnt/unraid/books cifs credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000,nofail 0 0

# Update .env:
KAVITA_LIBRARY_PATH=/mnt/unraid/books
```

### Immich with Unraid Photo Share
```bash
sudo mkdir -p /mnt/unraid/photos
# Add to /etc/fstab:
//192.168.1.100/photos /mnt/unraid/photos cifs credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000,nofail 0 0

# Update .env:
IMMICH_UPLOAD_PATH=/mnt/unraid/photos
```

### Paperless with Unraid Document Share
```bash
sudo mkdir -p /mnt/unraid/documents
# Add to /etc/fstab:
//192.168.1.100/documents /mnt/unraid/documents cifs credentials=/etc/smbcredentials/unraid,uid=1000,gid=1000,nofail 0 0

# Update .env:
PAPERLESS_MEDIA_PATH=/mnt/unraid/documents/paperless
PAPERLESS_CONSUME_PATH=/mnt/unraid/scans/inbox
```

## See Also

- [File Paths Quick Reference](./file-paths-reference.md) - All configurable paths
- [File Mounts Configuration Guide](./file-mounts-guide.md) - Complete setup guide
- [Navidrome Setup](./navidrome-setup.md) - Service-specific configuration
