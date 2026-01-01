# Pi-Hole Setup Guide

Pi-Hole is a network-wide ad blocker that acts as a DNS sinkhole, blocking ads and trackers at the DNS level for all devices on your network.

**In the Weekend Stack, Pi-hole also provides DNS resolution for `.lab` domains.** This is the recommended method for accessing your services.

## Overview

- **Container:** `pihole/pihole:latest`
- **Profile:** `networking` or `all`
- **Compose File:** `docker-compose.networking.yml`
- **Access:** Internal network only (NOT exposed via Traefik/Cloudflare)
- **Primary Purpose:** Network-wide ad blocking + local DNS for `.lab` domains

## Quick Start

### 1. Configure Environment Variables

The following variables are available in `.env`:

```bash
# Pi-Hole Configuration
PIHOLE_PORT_WEB=8088          # Web admin interface port
PIHOLE_PORT_DNS=53            # DNS server port (REQUIRED - do not change)
PIHOLE_MEMORY_LIMIT=512m      # Container memory limit
PIHOLE_WEBPASSWORD=your-password-here  # Admin panel password
PIHOLE_DNS1=1.1.1.1           # Primary upstream DNS (Cloudflare)
PIHOLE_DNS2=1.0.0.1           # Secondary upstream DNS (Cloudflare)
```

⚠️ **Important:** `PIHOLE_PORT_DNS` MUST be `53` for routers, macOS, iOS, and most other devices to use it.

### 2. Start Pi-Hole

```bash
# Start with networking profile
docker compose --profile networking up -d

# Or start all services
docker compose --profile all up -d
```

Pi-hole will automatically generate wildcard DNS configuration for `*.lab` domains on first start.

### 3. Access the Admin Interface

Open your browser to: `http://<your-server-ip>:8088/admin`

Login with the password set in `PIHOLE_WEBPASSWORD`.

### 4. Configure Devices to Use Pi-hole

**This is the critical step!** Pi-hole is running and configured, but your devices need to be told to use it for DNS.

📖 **See the complete guide:** [docs/dns-setup-guide.md](dns-setup-guide.md)

**Quick Summary:**
- **Best:** Configure your router's DHCP to hand out Pi-hole's IP as DNS server
- **Alternative:** Configure each device individually to use Pi-hole's IP
- **Testing only:** Add entries to /etc/hosts on each device

## Local DNS for .lab Domains

Pi-hole is pre-configured with wildcard DNS for the `.lab` domain:

## Port Configuration

Pi-hole uses standard DNS port 53. **Do not change this** - most devices require DNS on port 53.

### Default Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8088 | TCP | Web admin interface |
| 53 | TCP/UDP | DNS server |

### Port 53 Conflict (systemd-resolved on Linux)

On most Linux systems, `systemd-resolved` uses port 53. You **must** disable it to use Pi-hole:

**Steps to free port 53:**

1. Edit `/etc/systemd/resolved.conf`:
   ```bash
   sudo nano /etc/systemd/resolved.conf
   ```

2. Add or uncomment these lines:
   ```ini
   [Resolve]
   DNSStubListener=no
   ```

3. Restart systemd-resolved:
   ```bash
   sudo systemctl restart systemd-resolved
   ```

4. Verify port 53 is free:
   ```bash
   sudo ss -lntu | grep :53
   # Should show nothing
   ```

5. Recreate the Pi-hole container:
   ```bash
   docker compose --profile networking up -d pihole --force-recreate
   ```

6. Verify Pi-hole is listening:
   ```bash
   sudo ss -lntu | grep :53
   # Should show docker-proxy on port 53
   ```

## Using Pi-Hole for .lab Domains

**After configuring your devices to use Pi-hole** (see [dns-setup-guide.md](dns-setup-guide.md)), all `.lab` domains will automatically work:

- ✅ `http://home.lab` → Your Glance dashboard
- ✅ `http://coder.lab` → Coder IDE  
- ✅ `http://gitlab.lab` → GitLab instance
- ✅ Any other service at `http://[service].lab`

**How it works:**
1. Your device asks Pi-hole: "Where is coder.lab?"
2. Pi-hole checks its local DNS rules
3. Pi-hole finds wildcard rule: `*.lab → 192.168.2.50`
4. Pi-hole responds: "coder.lab is at 192.168.2.50"
5. Your browser connects to Traefik at 192.168.2.50
6. Traefik routes to the correct container based on hostname

## Configuring Devices to Use Pi-hole

See the comprehensive guide: [docs/dns-setup-guide.md](dns-setup-guide.md)

**Quick reference for common scenarios:**

### Router-Level (Recommended - Affects All Devices)

**UniFi:**
- Settings → Networks → LAN → DHCP Name Server → Manual
- DNS Server 1: `192.168.2.50`
- Apply Changes

**Generic Router:**
- Find DHCP settings
- Set Primary DNS to your server's IP (`192.168.2.50`)
- Devices will use Pi-hole after DHCP renewal

### Per-Device (If router access unavailable)

**Linux:**
```bash
sudo resolvectl dns [interface] 192.168.2.50
```

**macOS:**
- System Settings → Network → Wi-Fi → Details → DNS
- Add: `192.168.2.50`

**Windows:**
- Settings → Network & Internet → Wi-Fi → Edit DNS
- Manual IPv4: `192.168.2.50`

**iOS/Android:**
- Wi-Fi settings → Tap network → Configure DNS
- Manual → Add `192.168.2.50`

## Verification

After configuring DNS, verify Pi-hole is working:

```bash
# Run diagnostic tool
cd /opt/stacks/weekendstack
bash tools/diagnose_lab.sh

# Manual DNS test
dig @192.168.2.50 coder.lab
# Should return: 192.168.2.50

# System DNS test (after configuring device)
dig coder.lab
# Should return: 192.168.2.50
```

**Browser test:**
Visit http://home.lab - should load the Glance dashboard.

## Ad Blocking Features

In addition to local DNS, Pi-hole provides network-wide ad blocking:

### View Statistics

Visit the admin interface: `http://192.168.2.50:8088/admin`

**Dashboard shows:**
- Total queries today
- Queries blocked today
- Percent blocked
- Top blocked domains
- Top clients (devices making queries)

### Managing Blocklists

**Default blocklists** are enabled automatically. To add more:

1. Go to **Group Management** → **Adlists**
2. Add a blocklist URL
3. Click **Add**
4. Go to **Tools** → **Update Gravity**
5. Click **Update**

**Popular blocklists:**
- Steven Black's hosts: `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
- OISD Big: `https://big.oisd.nl/`

### Whitelist/Blacklist

**Whitelist** (allow blocked domains):
1. Go to **Whitelist**
2. Add domain (e.g., `example.com`)
3. Click **Add to Whitelist**

**Blacklist** (block allowed domains):
1. Go to **Blacklist**
2. Add domain
3. Click **Add to Blacklist**

## Troubleshooting

### Pi-hole not resolving .lab domains

**Check wildcard DNS config:**
```bash
docker exec pihole cat /etc/dnsmasq.d/05-pihole-custom-cname.conf
# Should contain: address=/.lab/192.168.2.50
```

**If missing, regenerate:**
```bash
docker compose --profile networking up -d pihole-dnsmasq-init --force-recreate
docker compose restart pihole
```

### Devices not using Pi-hole

**Check current DNS server:**
```bash
# Linux
resolvectl status | grep "DNS Servers"

# macOS  
scutil --dns | grep nameserver

# Windows
ipconfig /all | findstr "DNS Servers"
```

**Expected:** Should show `192.168.2.50`

**If wrong:** Reconfigure device or router per [dns-setup-guide.md](dns-setup-guide.md)

### Pi-hole container won't start (port 53 conflict)

**Check what's using port 53:**
```bash
sudo ss -lnpu | grep :53
```

**Common culprits:**
- `systemd-resolved` - See "Port 53 Conflict" section above
- Another DNS server (dnsmasq, bind9) - Stop or reconfigure it
- Another Docker container - Check `docker compose ps`

### DNS queries slow

**Check upstream DNS:**
1. Visit Pi-hole admin → Settings → DNS
2. Try different upstream servers:
   - Cloudflare: `1.1.1.1`, `1.0.0.1`
   - Google: `8.8.8.8`, `8.8.4.4`
   - Quad9: `9.9.9.9`, `149.112.112.112`

**Check Pi-hole logs:**
```bash
docker compose logs pihole | tail -50
```

## Next Steps

1. ✅ **Configure DNS** - Follow [dns-setup-guide.md](dns-setup-guide.md)
2. **Enable HTTPS** - See [local-https-setup.md](local-https-setup.md)
3. **Customize Ad Blocking** - Add blocklists in Pi-hole admin
4. **Monitor Network** - Check Pi-hole dashboard for query statistics
4. If using non-standard port (5353), check if your router supports custom DNS ports

> **Note:** Most consumer routers only support standard port 53 for DNS. If using port 5353, you'll need to configure devices individually or set up a port forward.

## macOS (Ethernet/Wi‑Fi) - Force Pi-hole as DNS

Goal: make your Mac use only `192.168.2.50` for DNS so `*.lab` resolves 100% consistently.

1. Set DNS on the active interface (GUI):
   - System Settings → Network → (Ethernet) → Details… → DNS
   - Add your server IP (the value of `HOST_IP` in `.env`)
   - Remove any other DNS servers

2. Ensure macOS is actually using it:
   ```bash
   scutil --dns | sed -n '1,200p'
   ```
   Look for `nameserver[...] : 192.168.2.50`. If you see other resolvers, something else is still providing DNS (VPN profile, Secure DNS/DoH, etc.).

3. Deterministic DNS test (bypasses macOS resolver caching):
   ```bash
   dig @192.168.2.50 gitlab.lab +short
   dig @192.168.2.50 random123.lab +short
   ```
   Expected output: your server IP (the value of `HOST_IP`).

## Local DNS for `*.lab`

This repo is designed so a fresh checkout does not require editing dnsmasq files to match your LAN.

- On startup, the `pihole-dnsmasq-init` compose service generates a wildcard so `*.lab` resolves to `HOST_IP`.
- If you change `HOST_IP`, just recreate Pi-hole (or rerun the `networking` profile) and the rule updates.

Traefik note:
- With the `networking` profile running, Traefik listens on port 80 and routes `http://<service>.lab`.
- Unknown `*.lab` hostnames are redirected to `http://home.lab/` to avoid a Traefik 404.

4. Flush DNS cache (optional, helps after changes):
   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```

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
| `./config/pihole/etc-pihole` | `/etc/pihole` | Pi-Hole configuration and lists |
| `./config/pihole/etc-dnsmasq.d` | `/etc/dnsmasq.d` | dnsmasq configuration |

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
dig @<your-server-ip> google.com

# Check if Pi-Hole is blocking ads
dig @<your-server-ip> ads.google.com
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
