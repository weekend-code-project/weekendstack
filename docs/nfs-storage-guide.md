# NFS Storage Guide

This guide covers configuring NFS (Network File System) storage for WeekendStack services to offload large data sets from VM storage to a NAS (Network Attached Storage) server.

## Overview

By default, WeekendStack services store data on the Docker host VM in `./files/` and `./data/` directories. For large media libraries, AI models, or document collections, storing data on NFS can:

- **Preserve VM disk space** for Docker images and system files
- **Centralize storage** on dedicated NAS hardware (e.g., Unraid, TrueNAS, Synology)
- **Share data** across multiple machines or services
- **Simplify backups** by keeping data on NAS with existing backup solutions

## Architecture

WeekendStack uses Docker's local volume driver with NFS backend. This approach:
- Eliminates need for host-level `/etc/fstab` NFS mounts
- Manages NFS connections inside Docker
- Provides clean volume abstraction
- Works consistently across Docker hosts

## Services with NFS Support

### Phase 1: Implemented (v0.2.4)

| Service | Category | Data Type | Typical Size | Read/Write | Setup Doc |
|---------|----------|-----------|--------------|------------|-----------|
| **Immich** | Personal | Photos/Videos | 10GB-1TB+ | Read/Write | [immich-setup.md](immich-setup.md) |
| **Navidrome** | Media | Music library | 10GB-500GB | Read/Write | [navidrome-setup.md](navidrome-setup.md) |
| **Kavita** | Media | eBooks/Comics | 5GB-200GB | Read/Write | [kavita-setup.md](kavita-setup.md) |
| **Ollama** | AI | LLM models | 1GB-200GB | Read/Write | [ollama-setup.md](ollama-setup.md) |

### Phase 2: Planned

| Service | Category | Data Type | Typical Size | Notes |
|---------|----------|-----------|--------------|-------|
| **Paperless-NGX** | Productivity | Documents | 1GB-100GB | Multiple volumes (media, consume, export) |
| **ResourceSpace** | Productivity | Digital assets | 10GB-1TB+ | Purpose-built for large media collections |
| **GitLab** | Dev | Git repositories | 1GB-500GB | Performance-sensitive (git operations) |
| **Gitea** | Dev | Git repositories | 500MB-100GB | Lighter than GitLab |
| **Docker Registry** | Dev | Image cache | 5GB-200GB | Large sequential I/O |
| **Home Assistant** | Automation | Config/recordings | 1GB-100GB | Only if using camera recordings |

## NFS Server Setup

### Unraid Configuration

1. **Create Share**
   - Go to **Shares** → **Add Share**
   - Name: `photos`, `music`, `ollama-models`, etc. (service-specific)
   - Enable **Export**: Yes
   - Set **Security**: Private

2. **Configure NFS Export**
   - Edit `/boot/config/nfs-exports.cfg` or use Unraid UI
   - Add export rule:
     ```
     /mnt/user/photos 192.168.2.0/24(sec=sys,rw,no_subtree_check,all_squash,anonuid=99,anongid=100)
     ```
   - Adjust subnet (`192.168.2.0/24`) to match your network
   - Use `rw` (read-write) for all services to allow file uploads

3. **NFS Export Options Explained**
   - `sec=sys`: Standard Unix permissions
   - `rw` or `ro`: Read-write or read-only access
   - `no_subtree_check`: Improves performance, safe for Docker usage
   - `all_squash`: Map all users to anonymous user (recommended for Docker)
   - `anonuid=99,anongid=100`: Map to `nobody:users` (Unraid default)

4. **Verify Export**
   ```bash
   # On Docker host
   showmount -e 192.168.2.3
   ```

### TrueNAS Configuration

1. **Create Dataset**
   - Storage → Pools → Add Dataset
   - Name: `photos`, `music`, etc.

2. **Create NFS Share**
   - Sharing → Unix Shares (NFS) → Add
   - Path: Select dataset
   - Network: `192.168.2.0/24`
   - Maproot User: `nobody`
   - Maproot Group: `nogroup`

3. **Enable NFS Service**
   - Services → NFS → Start Automatically: Yes

### Synology NAS Configuration

1. **Create Shared Folder**
   - Control Panel → Shared Folder → Create

2. **Enable NFS**
   - Control Panel → File Services → NFS → Enable NFSv4
   - Edit shared folder → NFS Permissions → Create
   - Hostname/IP: Docker host IP
   - Privilege: Read/Write or Read-only
   - Squash: Map all users to admin (or specific UID)

## WeekendStack Configuration

### Step 1: Configure Environment Variables

Edit `.env` and add/uncomment:

```bash
# NFS Server Configuration (shared across all NFS-enabled services)
NFS_SERVER_IP=192.168.2.3

# Service-specific NFS paths
NFS_PHOTOS_PATH=/mnt/user/photos/immich-uploads
NFS_NAVIDROME_PATH=/mnt/user/music
NFS_KAVITA_PATH=/mnt/user/books-and-comics
NFS_OLLAMA_PATH=/mnt/user/ollama-models
```

**Important**: Keep `NFS_SERVER_IP` consistent across all services. Only change service-specific paths.

### Step 2: Enable NFS Volume in Docker Compose

For each service you want to use NFS storage:

1. Open the appropriate `docker-compose.*.yml` file
2. Find the volumes section at the bottom
3. Uncomment the NFS volume definition
4. In the service definition, comment out the bind mount and uncomment the NFS volume mount

**Example: Navidrome**

Edit `compose/docker-compose.media.yml`:

```yaml
# In the navidrome service:
volumes:
  # - type: bind               # Comment out local bind mount
  #   source: ${NAVIDROME_MUSIC_PATH:-./files/navidrome/music}
  #   target: /music
  #   read_only: true
  #   bind:
  #     create_host_path: true
  - type: volume                # Uncomment NFS volume
    source: navidrome-nfs-music
    target: /music

# At the bottom of the file:
volumes:
  navidrome-data:
  navidrome-nfs-music:          # Uncomment NFS volume definition
    driver: local
    driver_opts:
      type: nfs
      o: "addr=${NFS_SERVER_IP:-192.168.2.3},rw,nfsvers=4,nolock"
      device: ":${NFS_NAVIDROME_PATH:-/mnt/user/navidrome-music}"
```

### Step 3: Initialize Folder Structure (if required)

Some services (like Immich) require specific folder structures. Use the initialization script:

```bash
# For Immich
./tools/init-nfs-service.sh immich upload library profile thumbs encoded-video backups

# For other services (if needed)
./tools/init-nfs-service.sh ollama models
```

Most services work without initialization and will create directories automatically.

### Step 4: Restart Service

```bash
# Restart specific service
docker compose down SERVICE_NAME
docker compose --profile PROFILE up -d SERVICE_NAME

# Or restart all services
docker compose down
docker compose --profile all up -d
```

### Step 5: Verify NFS Mount

```bash
# Check volume is using NFS
docker volume inspect weekendstack_SERVICE-nfs-VOLUME

# Check inside container
docker compose exec SERVICE_NAME ls -la /mount/path

# Verify files appear on NFS server
# Check the NFS share on your NAS - uploaded files should appear there
```

## NFS Mount Options

WeekendStack uses these NFS mount options:

```
addr=<NFS_SERVER_IP>,rw,nfsvers=4,nolock
```

### Standard Options
- `addr=IP`: NFS server IP address
- `rw`: Read-write access (required for file uploads)
- `nfsvers=4`: Use NFSv4 protocol (more efficient, better security)
- `nolock`: Disable file locking (safe for Docker, improves performance)

### Incompatible Options (DO NOT USE with Docker NFS driver)
- ❌ `rsize`, `wsize`: Read/write buffer sizes
- ❌ `async`: Asynchronous writes
- ❌ `noatime`: Don't update access times
- ❌ `nofail`: Don't fail boot if mount fails

Docker's NFS driver handles these internally and will fail with "invalid argument" if you include them.

## Performance Considerations

### Good for NFS
- **Media streaming** (music, video): Sequential reads, large files
- **Photo uploads**: Large files, infrequent access
- **AI model storage**: Very large files, infrequent reads
- **Document archives**: Moderate file sizes, read-mostly workloads

### Caution with NFS
- **Databases**: High random I/O, latency-sensitive → keep on local storage
- **Git repositories**: Many small files, performance-sensitive → test carefully
- **Live transcoding**: High throughput requirements → may be slower
- **SQLite databases**: File locking issues → keep on local storage

### Network Requirements
- **Minimum**: 1 Gigabit Ethernet (125 MB/s)
- **Recommended**: 10 Gigabit Ethernet (1.25 GB/s) or NVMe-based NAS
- **Latency**: <2ms ping time between Docker host and NAS

### Performance Testing

Test NFS performance before migrating large services:

```bash
# Create test volume
docker volume create \
  --driver local \
  --opt type=nfs \
  --opt o=addr=192.168.2.3,rw,nfsvers=4,nolock \
  --opt device=:/mnt/user/test \
  nfs-test

# Write test (1GB file)
docker run --rm -v nfs-test:/data alpine sh -c \
  "dd if=/dev/zero of=/data/test.bin bs=1M count=1024 conv=fdatasync"

# Read test
docker run --rm -v nfs-test:/data alpine sh -c \
  "dd if=/data/test.bin of=/dev/null bs=1M"

# Cleanup
docker volume rm nfs-test
```

## Troubleshooting

### Connection Issues

**"Connection refused" or "No route to host"**
- Check NFS server is reachable: `ping 192.168.2.3`
- Verify firewall allows NFS traffic (ports 2049, 111)
- Ensure NFS service is running on server

**"Permission denied"**
- Check NFS export permissions (should include Docker host IP)
- Verify `all_squash,anonuid=99,anongid=100` in export
- Check file permissions on NFS server

**"Stale file handle"**
- NFS export was modified after mount
- Restart service: `docker compose restart SERVICE_NAME`
- If persists, restart Docker: `sudo systemctl restart docker`

### Volume Issues

**"invalid argument" when creating volume**
- Remove incompatible mount options (rsize, wsize, async, etc.)
- Use only: `addr=IP,rw,nfsvers=4,nolock`
- Verify NFS path exists on server

**"No such file or directory"**
- Check `NFS_*_PATH` variable matches NFS export path exactly
- Verify export path on NFS server: `showmount -e NFS_SERVER_IP`
- Check for typos in device path (must start with `:`)

**Volume exists but is empty**
- Check NFS export permissions
- Verify path on NFS server has data
- Inspect volume: `docker volume inspect VOLUME_NAME`

### Performance Issues

**Slow file access**
- Test network speed between Docker host and NAS
- Check NAS isn't overloaded (CPU, disk I/O)
- Consider local SSD cache on NAS (if supported)
- Verify using NFSv4 (not NFSv3)

**Timeouts during large operations**
- Increase network timeout settings on NFS server
- Check network for packet loss: `ping -c 100 NFS_SERVER_IP`
- Ensure NAS has sufficient RAM for NFS cache

## Migration from Local to NFS

To migrate existing data from local storage to NFS:

1. **Backup existing data**: `tar czf backup.tar.gz ./files/SERVICE`

2. **Copy data to NFS server**: Use NAS web UI, SMB, or rsync

3. **Update configuration**: Follow steps above to enable NFS

4. **Test access**: Verify service can read/write to NFS

5. **Delete local copy** (only after confirming NFS works):
   ```bash
   rm -rf ./files/SERVICE
   ```

## Switching Back to Local Storage

To revert from NFS to local storage:

1. **Copy data from NFS**: Download data from NAS to `./files/SERVICE`

2. **Edit docker-compose file**: Comment out NFS volume, uncomment bind mount

3. **Restart service**:
   ```bash
   docker compose down SERVICE_NAME
   docker compose up -d SERVICE_NAME
   ```

## Security Considerations

### Network Security
- Use private network (192.168.x.x, 10.x.x.x)
- Don't expose NFS to internet
- Consider VLAN isolation for NAS traffic
- Use firewall rules to restrict NFS access to Docker host only

### Permission Mapping
- Use `all_squash` to prevent root escalation
- Map to `nobody:users` (99:100) or dedicated service UID
- Set proper file permissions on NAS (750 or 755 for directories)

### Data Protection
- Enable NFS over TLS/Kerberos (NFSv4.1+) if supported
- Consider VPN if NFS must cross network boundaries
- Regular backups of NFS data (on NAS itself)

## Best Practices

1. **One NFS share per service** for isolation and flexibility
2. **Document NFS paths** in .env.example for team members
3. **Test NFS connectivity** before migrating production data
4. **Monitor NFS performance** after migration
5. **Keep configs local** - only migrate large user data to NFS
6. **Use read-only** mounts where possible (music, read-only media)
7. **Regular backups** of both local and NFS data

## Related Documentation

- [immich-setup.md](immich-setup.md) - Immich NFS storage configuration
- [navidrome-setup.md](navidrome-setup.md) - Navidrome music library on NFS
- [kavita-setup.md](kavita-setup.md) - Kavita eBook library on NFS
- [ollama-setup.md](ollama-setup.md) - Ollama AI model storage on NFS
- [file-mounts-guide.md](file-mounts-guide.md) - General volume concepts
