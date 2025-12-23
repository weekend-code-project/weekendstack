# Local Access Setup Guide

This guide explains how to access your Weekend Stack services locally without going through the Cloudflare tunnel, using dual-domain routing with Traefik.

## Overview

After implementing this setup, each service will be accessible via **two domains**:

1. **Public Domain** (`*.weekendcodeproject.dev`): 
   - Routes through Cloudflare tunnel
   - Accessible from anywhere on the internet
   - Uses valid SSL certificates from Cloudflare

2. **Local Domain** (`*.lab`):
   - Routes directly to your local Traefik instance
   - Only accessible from your local network
   - Faster response times (no internet roundtrip)
   - No bandwidth usage on your internet connection

> **Note:** We use `.lab` instead of `.local` because `.local` is reserved for mDNS/Bonjour and can cause conflicts.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Internet Access (from anywhere)                            │
└─────────────────────────────────────────────────────────────┘

https://gitlab.weekendcodeproject.dev
    ↓
Cloudflare Tunnel (encrypted)
    ↓
Traefik (192.168.2.50:443)
    ↓
GitLab Container


┌─────────────────────────────────────────────────────────────┐
│  Local Access (from your home network)                      │
└─────────────────────────────────────────────────────────────┘

https://gitlab.lab
    ↓
Router DNS (*.lab → 192.168.2.50) or /etc/hosts lookup
    ↓
Traefik (192.168.2.50:443)
    ↓
GitLab Container (same container!)
```

**Key Points:**
- Both domains route to the **same** Traefik instance
- Both domains reach the **same** containers
- Traefik uses the HTTP `Host` header to route requests
- All services accessible on the same IP and ports (80/443)
- Differentiated only by hostname

## Prerequisites

- Weekend Stack running with Traefik
- Server IP address: `192.168.2.50` (adjust if different)
- Administrator access to client devices

---

## Implementation Plan

### Phase 1: Update Traefik Labels (Server-Side)

All service definitions in the Docker Compose files need updated Traefik labels to accept both domains.

**Current Label:**
```yaml
- traefik.http.routers.gitlab.rule=Host(`gitlab.${BASE_DOMAIN}`)
```

**New Label:**
```yaml
- traefik.http.routers.gitlab.rule=Host(`gitlab.${BASE_DOMAIN}`) || Host(`gitlab.lab`)
```

**Services to Update:**
- Development: gitlab, gitea, coder
- Productivity: postiz, nocodb, paperless-ngx, n8n, focalboard, trilium, vikunja, docmost, activepieces, bytestash, excalidraw, it-tools
- Personal: mealie, firefly, wger
- Monitoring: dozzle, wud, uptime-kuma, netdata, portainer, duplicati, netbox
- Media: immich-server, kavita, navidrome
- AI: open-webui, librechat, anythingllm, searxng, localai
- Core: homer, vaultwarden
- Networking: traefik (dashboard), pihole
- Automation: homeassistant, nodered

After updating labels, restart services:
```bash
docker compose up -d --force-recreate
```

### Phase 2: DNS Configuration

Choose **ONE** of the following options:

---

#### Option A: UniFi Network (Recommended for UniFi Users)

Configure wildcard DNS at the router level - all devices on your network automatically get the configuration!

1. **Access UniFi Controller:**
   - Navigate to your UniFi controller (typically https://unifi.ui.com or local controller)
   - Go to **Settings** → **Networks**

2. **Configure DNS:**
   - Select your LAN network (usually "Default")
   - Scroll to **DHCP Name Server**
   - Set to "Manual" if not already
   - Note the DNS server IP (this should be your UniFi gateway)

3. **Add Custom DNS Records:**
   - Go to **Settings** → **System** → **Advanced**
   - Enable **Advanced Features** if not already enabled
   - Look for **DNS** or **Custom DNS** settings

4. **SSH to UniFi Gateway/Controller:**
   ```bash
   ssh admin@<unifi-gateway-ip>
   ```

5. **Add Wildcard DNS Entry:**
   ```bash
   # Edit dnsmasq configuration
   configure
   set service dns forwarding options 'address=/lab/192.168.2.50'
   commit
   save
   exit
   ```

6. **Verify Configuration:**
   ```bash
   # From any device on your network
   nslookup gitlab.lab
   # Should return: 192.168.2.50
   
   nslookup anything.lab
   # Should also return: 192.168.2.50
   ```

**Result:** Now `gitlab.lab`, `mealie.lab`, `portainer.lab`, or **any** subdomain of `.lab` automatically resolves to `192.168.2.50` for all devices on your network!

---

#### Option B: Manual Hosts File (Per Device)

If you can't configure router-level DNS, add entries manually on each device.

##### For Linux/macOS:

1. **Edit hosts file:**
   ```bash
   sudo nano /etc/hosts
   ```

2. **Add entries:** (adjust IP if your server uses different address)
   ```
   # Weekend Stack - Local Access
   192.168.2.50    gitlab.lab gitea.lab coder.lab postiz.lab nocodb.lab paperless.lab n8n.lab focalboard.lab trilium.lab vikunja.lab docmost.lab activepieces.lab bytestash.lab excalidraw.lab it-tools.lab mealie.lab firefly.lab wger.lab dozzle.lab wud.lab uptime.lab netdata.lab portainer.lab duplicati.lab netbox.lab immich.lab kavita.lab navidrome.lab chat.lab librechat.lab anythingllm.lab searxng.lab localai.lab homer.lab vaultwarden.lab traefik.lab pihole.lab homeassistant.lab nodered.lab
   ```
   
   **Alternative (one per line for readability):**
   ```
   # Weekend Stack - Local Access
   192.168.2.50    gitlab.lab
   192.168.2.50    gitea.lab
   192.168.2.50    coder.lab
   192.168.2.50    postiz.lab
   192.168.2.50    nocodb.lab
   192.168.2.50    paperless.lab
   192.168.2.50    n8n.lab
   192.168.2.50    focalboard.lab
   192.168.2.50    trilium.lab
   192.168.2.50    vikunja.lab
   192.168.2.50    docmost.lab
   192.168.2.50    activepieces.lab
   192.168.2.50    bytestash.lab
   192.168.2.50    excalidraw.lab
   192.168.2.50    it-tools.lab
   192.168.2.50    mealie.lab
   192.168.2.50    firefly.lab
   192.168.2.50    wger.lab
   192.168.2.50    dozzle.lab
   192.168.2.50    wud.lab
   192.168.2.50    uptime.lab
   192.168.2.50    netdata.lab
   192.168.2.50    portainer.lab
   192.168.2.50    duplicati.lab
   192.168.2.50    netbox.lab
   192.168.2.50    immich.lab
   192.168.2.50    kavita.lab
   192.168.2.50    navidrome.lab
   192.168.2.50    chat.lab
   192.168.2.50    librechat.lab
   192.168.2.50    anythingllm.lab
   192.168.2.50    searxng.lab
   192.168.2.50    localai.lab
   192.168.2.50    homer.lab
   192.168.2.50    vaultwarden.lab
   192.168.2.50    traefik.lab
   192.168.2.50    pihole.lab
   192.168.2.50    homeassistant.lab
   192.168.2.50    nodered.lab
   ```

3. **Save and close** (Ctrl+O, Enter, Ctrl+X in nano)

4. **Verify:**
   ```bash
   ping gitlab.lab
   # Should show: PING gitlab.lab (192.168.2.50)
   ```

##### For Windows:

1. **Open Notepad as Administrator:**
   - Search for "Notepad"
   - Right-click → "Run as administrator"

2. **Open hosts file:**
   - File → Open
   - Navigate to: `C:\Windows\System32\drivers\etc\hosts`
   - Change file type filter to "All Files (*.*)"

3. **Add the same entries** as above (starting with `# Weekend Stack - Local Access`)

4. **Save** (File → Save)

5. **Verify in Command Prompt:**
   ```cmd
   ping gitlab.lab
   ```

---

#### Option C: Other Routers with DNS Override Support

Many routers support custom DNS entries:

- **pfSense/OPNsense:** Services → DNS Resolver → Host Overrides → Add wildcard domain
- **DD-WRT:** Services → DNSMasq → Additional DNSMasq Options → `address=/lab/192.168.2.50`
- **OpenWrt:** Network → DHCP and DNS → Hostnames → Add custom entry
- **ASUS Merlin:** LAN → DNSFilter → Custom → Add dnsmasq config
- **Mikrotik:** IP → DNS → Static → Add DNS record

Consult your router's documentation for specific instructions.

---

## Usage

### Accessing Services Locally

#### List All `.lab` Service URLs (Recommended)

Generate a current list of local URLs directly from the Traefik router rules in your compose files:

```bash
python3 tools/list_lab_urls.py
```

To include both local `.lab` and public `${BASE_DOMAIN}` hostnames:

```bash
python3 tools/list_lab_urls.py --all
```

Markdown table output (useful for pasting into notes):

```bash
python3 tools/list_lab_urls.py --format markdown
```

#### One-Command Health Check (DNS + Traefik)

This checks:
- Whether `traefik` and `pihole` are up
- Whether ports `53/80/443` are listening on the host
- Whether Pi-hole answers a direct DNS query for a `.lab` hostname
- Whether Traefik responds when you send the correct `Host:` header

```bash
bash tools/diagnose_lab.sh coder.lab
```

---

## Common Gotchas (When It “Works Sometimes”)

### 1) Secondary DNS Causes Split Behavior

If DHCP hands out **two DNS servers** (e.g. Pi-hole + `1.1.1.1`), some clients will randomly use the secondary server. Since `1.1.1.1` does not know your private `.lab` wildcard, you’ll see intermittent failures like:
- `nslookup coder.lab 192.168.2.50` works
- But `curl http://coder.lab` or a browser sometimes says “cannot resolve”

**Recommended:** on the LAN you want `.lab` to work on, use **Pi-hole as the only DNS server**.

### 2) VLAN / IoT Network Can’t Reach Pi-hole or Traefik

If your phone/PC is on a different network (IoT/Guest/VLAN) it may be blocked from reaching:
- Pi-hole: UDP/TCP `53` to `192.168.2.50`
- Traefik: TCP `80/443` to `192.168.2.50`

**Recommended:** either set that network’s DNS to Pi-hole too, and allow traffic to the ports above, or accept that `.lab` only works on your main LAN.

Once configured, simply use the `.lab` domain in your browser:

- **GitLab:** https://gitlab.lab
- **Mealie:** https://mealie.lab
- **Firefly:** https://firefly.lab
- **Open WebUI:** https://chat.lab
- **Portainer:** https://portainer.lab

### Accessing Services Remotely

When away from your local network, use the `.weekendcodeproject.dev` domain:

- **GitLab:** https://gitlab.weekendcodeproject.dev
- **Mealie:** https://mealie.weekendcodeproject.dev
- **Firefly:** https://firefly.weekendcodeproject.dev

Both URLs reach the **same application** with the **same data**.

---

## SSL Certificate Considerations

### Local Domain (*.lab)

When accessing `*.lab` domains, you may see SSL certificate warnings because:
- Traefik's certificate is for `*.weekendcodeproject.dev`, not `*.lab`
- Self-signed certificates won't match `*.lab` domains

**Options:**

1. **Accept the Warning** (easiest):
   - Click "Advanced" → "Proceed to site" in your browser
   - Browser will remember your exception

2. **Use HTTP for Local Access** (no encryption):
   - Access via `http://gitlab.lab` instead of `https://`
   - Only do this if you trust your local network

3. **Set Up Local CA** (advanced):
   - Generate a local Certificate Authority
   - Issue certificates for `*.lab`
   - Install CA certificate on all client devices
   - Configure Traefik to use local certs for `*.lab` domains

### Public Domain (*.weekendcodeproject.dev)

No certificate warnings - Cloudflare provides valid SSL certificates.

---

## Troubleshooting

### "Can't reach gitlab.lab"

1. **Verify DNS resolution:**
   ```bash
   nslookup gitlab.lab
   # Should show: Server pointing to 192.168.2.50
   
   # Or use ping
   ping gitlab.lab
   # Should show: PING gitlab.lab (192.168.2.50)
   ```

2. **If using router DNS (Option A):**
   - Verify the dnsmasq configuration is active: SSH to router and check `/etc/dnsmasq.conf` or run `configure; show service dns`
   - Restart DNS on the router if needed
   - Ensure device is using router as DNS server (check network settings)

3. **If using hosts file (Option B):**
   ```bash
   cat /etc/hosts | grep gitlab.lab
   # Should show: 192.168.2.50    gitlab.lab
   ```

3. **Verify server is reachable:**
   ```bash
   ping 192.168.2.50
   # Should show responses
   ```

4. **Verify Traefik is running:**
   ```bash
   docker ps | grep traefik
   # Should show traefik container
   ```

### "Connection refused" or "No route to host"

- Ensure you're on the same network as the server (192.168.2.x)
- Check firewall rules on server (ports 80/443 should be open)
- Verify server IP hasn't changed

### Wrong Certificate / SSL Error

- This is expected for `*.lab` domains
- See "SSL Certificate Considerations" above

### Wildcard DNS Not Working (Router Option)

- **UniFi:** Ensure you're running UniFi OS 3.0+ or USG/UDM with custom dnsmasq support
- **Persistence:** Some routers clear custom dnsmasq configs on reboot - may need to add via startup script
- **Alternative:** Use UniFi's DNS Records feature if available in newer firmware
- **Test:** Try `nslookup randomname.lab` - should still return `192.168.2.50`

### Service Not Found (404 from Traefik)

- Verify the service is running: `docker ps | grep <service>`
- Check Traefik labels were updated correctly
- Verify you restarted services after label changes

---

## Alternative: Pi-hole for Network-Wide DNS

If you have Pi-hole running in your stack, you can configure wildcard DNS there instead of using your router.

### Pi-hole Wildcard DNS Configuration

1. **SSH to Pi-hole host or container:**
   ```bash
   docker exec -it pihole bash
   ```

2. **Add wildcard DNS rule:**
   ```bash
   echo "address=/lab/192.168.2.50" >> /etc/dnsmasq.d/02-custom.conf
   ```

3. **Restart Pi-hole DNS:**
   ```bash
   pihole restartdns
   ```

4. **Configure devices to use Pi-hole as DNS server:**
   - **Option A (Network-wide):** Set DNS server to `192.168.2.50` in router DHCP settings
   - **Option B (Per device):** Manually configure DNS on each device

5. **Verify:**
   ```bash
   nslookup gitlab.lab
   nslookup anythingelse.lab
   # Both should return: 192.168.2.50
   ```

**Advantages:**
- True wildcard resolution like router method
- No need to edit hosts files on individual devices
- Centralized management
- Works with any subdomain automatically

**Disadvantages:**
- Requires Pi-hole to be running
- Requires network configuration changes or per-device DNS settings

---

## Benefits of This Setup

✅ **Fast Local Access:** No internet roundtrip for local requests  
✅ **Bandwidth Savings:** Local traffic doesn't use your internet connection  
✅ **Works During Outages:** Access services even if internet is down  
✅ **Same URLs Work Everywhere:** Use `.lab` at home, `.weekendcodeproject.dev` remotely  
✅ **No Additional Infrastructure:** Uses existing Traefik setup  
✅ **Same Data:** Both domains access the same containers/databases  
✅ **Wildcard Support:** Router/Pi-hole DNS makes ANY `.lab` subdomain work automatically  

---

## Security Notes

- The `.lab` domains bypass Cloudflare's protection
- Ensure your local network is secure (WPA3, strong WiFi password)
- Consider enabling Traefik authentication for sensitive services
- Router-level DNS affects all devices on the network - ensure router admin access is protected
- If using Pi-hole method, protect Pi-hole admin interface with strong password

---

## Summary

This dual-domain setup gives you:
- **Local network:** Fast, direct access via `*.lab` domains
- **Internet:** Secure, remote access via `*.weekendcodeproject.dev` domains
- **Same services:** Both domains reach identical containers
- **Flexibility:** Choose the best access method for your location

The implementation requires:
1. **Server-side:** Update Traefik labels to accept both domains
2. **Network-side:** Configure wildcard DNS on router (recommended) OR add hosts file entries on each device

**Recommended approach for UniFi users:** Configure wildcard DNS at the router level for automatic network-wide access!

Once configured, you'll have seamless access to your services whether you're at home or away.
