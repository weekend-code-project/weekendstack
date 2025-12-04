# Pi-Hole Setup Guide

Pi-Hole is a network-wide ad blocker that acts as a DNS sinkhole, blocking ads and trackers at the DNS level for all devices on your network.

## Overview

- **Container:** `pihole/pihole:latest`
- **Profile:** `networking` or `all`
- **Compose File:** `docker-compose.networking.yml`
- **Access:** Internal network only (NOT exposed via Traefik/Cloudflare)

## Quick Start

### 1. Configure Environment Variables

The following variables are available in `.env`:

```bash
# Pi-Hole Configuration
PIHOLE_PORT_WEB=8088          # Web admin interface port
PIHOLE_PORT_DNS=5353          # DNS server port (default 53 may conflict with systemd-resolved)
PIHOLE_MEMORY_LIMIT=512m      # Container memory limit
PIHOLE_WEBPASSWORD=your-password-here  # Admin panel password
PIHOLE_DNS1=1.1.1.1           # Primary upstream DNS (Cloudflare)
PIHOLE_DNS2=1.0.0.1           # Secondary upstream DNS (Cloudflare)
```

### 2. Start Pi-Hole

```bash
# Start with networking profile
docker compose --profile networking --profile dev up -d pihole

# Or start all services
docker compose --profile all up -d
```

### 3. Access the Admin Interface

Open your browser to: `http://<your-server-ip>:8088/admin`

Login with the password set in `PIHOLE_WEBPASSWORD`.

## Port Configuration

### Default Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8088 | TCP | Web admin interface |
| 5353 | TCP/UDP | DNS server |

### Port 53 Conflict (systemd-resolved)

On most Linux systems, `systemd-resolved` uses port 53. You have two options:

#### Option A: Use Alternate Port (Default)

Pi-Hole runs on port 5353 by default in this stack. Devices must be configured to use this non-standard port, or you can set up port forwarding on your router.

#### Option B: Disable systemd-resolved Stub Listener

If you want Pi-Hole to use the standard port 53:

1. Edit `/etc/systemd/resolved.conf`:
   ```ini
   [Resolve]
   DNSStubListener=no
   ```

2. Restart systemd-resolved:
   ```bash
   sudo systemctl restart systemd-resolved
   ```

3. Update `.env`:
   ```bash
   PIHOLE_PORT_DNS=53
   ```

4. Recreate the container:
   ```bash
   docker compose --profile networking up -d pihole --force-recreate
   ```

## Using Pi-Hole as Your DNS Server

### For Individual Devices

Configure your device's DNS settings to point to your server's IP address and the configured DNS port.

- **DNS Server:** `<your-server-ip>`
- **Port:** `5353` (or `53` if you disabled systemd-resolved)

### For Entire Network (Router Configuration)

1. Access your router's admin interface
2. Find DHCP settings
3. Set the primary DNS server to your Pi-Hole server's IP
4. If using non-standard port (5353), check if your router supports custom DNS ports

> **Note:** Most consumer routers only support standard port 53 for DNS. If using port 5353, you'll need to configure devices individually or set up a port forward.

## Configuration Options

### Upstream DNS Servers

Configure upstream DNS providers in `.env`:

```bash
# Cloudflare (default)
PIHOLE_DNS1=1.1.1.1
PIHOLE_DNS2=1.0.0.1

# Google
PIHOLE_DNS1=8.8.8.8
PIHOLE_DNS2=8.8.4.4

# Quad9 (security focused)
PIHOLE_DNS1=9.9.9.9
PIHOLE_DNS2=149.112.112.112
```

### Memory Limits

Adjust based on your network size:

```bash
PIHOLE_MEMORY_LIMIT=512m   # Small network (< 20 devices)
PIHOLE_MEMORY_LIMIT=1g     # Medium network (20-100 devices)
PIHOLE_MEMORY_LIMIT=2g     # Large network (100+ devices)
```

## Data Persistence

Pi-Hole data is stored in bind mounts:

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `./files/pihole/etc-pihole` | `/etc/pihole` | Pi-Hole configuration and lists |
| `./files/pihole/etc-dnsmasq.d` | `/etc/dnsmasq.d` | dnsmasq configuration |

Directories are created automatically by Docker when the container starts.

## Updating Block Lists

1. Access the admin interface
2. Go to **Adlists** in the sidebar
3. Add or manage block list URLs
4. Run **Update Gravity** to apply changes

### Popular Block Lists

- **Default:** Pi-Hole includes sensible defaults
- **Steven Black's Hosts:** `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
- **OISD:** `https://dbl.oisd.nl/`

## Troubleshooting

### Check Container Status

```bash
docker compose ps pihole
docker logs pihole
```

### Verify DNS Resolution

```bash
# Test DNS query through Pi-Hole
dig @<your-server-ip> -p 5353 google.com

# Check if Pi-Hole is blocking ads
dig @<your-server-ip> -p 5353 ads.google.com
```

### Reset Admin Password

If you forget the password:

```bash
docker exec -it pihole pihole -a -p newpassword
```

Or update `PIHOLE_WEBPASSWORD` in `.env` and recreate the container:

```bash
docker compose --profile networking up -d pihole --force-recreate
```

### Container Won't Start

1. Check for port conflicts:
   ```bash
   ss -tulnp | grep :53
   ss -tulnp | grep :5353
   ```

2. Check logs:
   ```bash
   docker logs pihole
   ```

## Security Notes

- Pi-Hole is **NOT exposed via Traefik** - it's internal network access only
- Change the default password in production
- Consider restricting access to the admin interface by IP if needed
- DNS queries are logged by default - review Pi-Hole's privacy settings if concerned

## Integration with Other Services

Pi-Hole can be used alongside other stack services:

- **Traefik:** Routes HTTP traffic; Pi-Hole handles DNS only
- **Cloudflare Tunnel:** External access bypasses local DNS
- **Internal Services:** Can use Pi-Hole for internal DNS resolution

## References

- [Pi-Hole Documentation](https://docs.pi-hole.net/)
- [Pi-Hole Docker Hub](https://hub.docker.com/r/pihole/pihole)
- [Pi-Hole GitHub](https://github.com/pi-hole/docker-pi-hole)
