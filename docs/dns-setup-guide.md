# DNS Setup Guide for .lab Domains

**⚠️ REQUIRED STEP** - Your services won't be accessible via `.lab` domains until DNS is configured.

## Why DNS Configuration is Required

The Weekend Stack services use custom `.lab` domains (like `coder.lab`, `gitlab.lab`, etc.). These are not real internet domains - they're only for your local network. Your devices need to be told that these domains point to your server's IP address (`192.168.2.50` by default).

**Without DNS configuration:**
- ❌ Browser shows "Cannot resolve host" or "Server not found"
- ❌ `ping coder.lab` fails with "unknown host"
- ❌ Services are unreachable via `.lab` domains

**With DNS configuration:**
- ✅ Browser loads `http://coder.lab` successfully
- ✅ All `.lab` domains automatically work (wildcard DNS)
- ✅ No need to remember port numbers or IP addresses

---

## Quick Decision Tree

```
Do you have access to your router's admin interface?
├─ YES → Use Method 1 (Router-Level DNS) ← RECOMMENDED
│
└─ NO → Can all devices on your network use custom DNS?
    ├─ YES → Use Method 2 (Pi-hole as Network DNS)
    │
    └─ NO → Use Method 3 (/etc/hosts per device)
```

**Recommendation:** Method 1 (Router-Level) is best because:
- ✅ Automatically works for ALL devices on your network
- ✅ Works for phones, tablets, smart TVs, etc.
- ✅ No per-device configuration needed
- ✅ Supports ANY `.lab` subdomain automatically (wildcard)

---

## Method 1: Router-Level DNS (Recommended)

Configure your router to resolve `*.lab` domains to your server. This works network-wide for all devices.

### UniFi Dream Machine / Network

1. **Access UniFi Controller**
   - Navigate to https://unifi.ui.com or your local controller
   - Log in with your admin credentials

2. **Configure DNS**
   - Go to **Settings** → **Networks** → Select your LAN
   - Scroll to **DHCP Name Server**
   - Change to **Manual**
   - Set **DNS Server 1** to: `192.168.2.50` (your server IP)
   - Set **DNS Server 2** to: `1.1.1.1` (fallback for internet)
   - Click **Apply Changes**

3. **Renew DHCP on Clients**
   - Devices will get new DNS settings on next DHCP renewal
   - Or manually reconnect to WiFi on each device
   - Or run: `sudo dhclient -r && sudo dhclient` (Linux)

### pfSense / OPNsense

1. **Access Admin Interface**
   - Navigate to your router's admin page
   - Log in with admin credentials

2. **Add DNS Override**
   - Go to **Services** → **DNS Resolver** (Unbound)
   - Click **Host Overrides** tab
   - Click **Add**
   - **Host:** `*` (wildcard)
   - **Domain:** `lab`
   - **IP Address:** `192.168.2.50`
   - **Description:** Weekend Stack services
   - Click **Save** → **Apply Changes**

3. **Configure DHCP (Optional but Recommended)**
   - Go to **Services** → **DHCP Server**
   - Select your LAN interface
   - Under **Servers**, set DNS servers:
     - DNS Server 1: `192.168.2.50`
     - DNS Server 2: `1.1.1.1`
   - Click **Save**

### DD-WRT

1. **Access Admin Interface**
   - Navigate to your router (usually http://192.168.1.1)

2. **Add DNS Entry**
   - Go to **Services** → **DNSMasq**
   - Enable **DNSMasq**
   - In **Additional DNSMasq Options**, add:
     ```
     address=/lab/192.168.2.50
     ```
   - Click **Save** → **Apply Settings**

### Other Routers

Most consumer routers don't support wildcard DNS. If yours doesn't, use Method 2 or 3 instead.

---

## Method 2: Pi-hole as Network DNS

The Weekend Stack includes Pi-hole with wildcard DNS already configured. Just point your devices to use it.

### A. Router-Level (Easiest)

1. **Access Your Router's Admin Interface**
   - Find your router's IP (usually `192.168.1.1` or `192.168.0.1`)
   - Log in with admin credentials

2. **Change DHCP DNS Settings**
   - Look for: **DHCP Settings**, **LAN Settings**, or **DNS Configuration**
   - Find **Primary DNS Server** or **DNS Server 1**
   - Change from automatic/ISP to: `192.168.2.50`
   - Set **Secondary DNS** to: `1.1.1.1` (optional fallback)
   - Save and restart router if required

3. **Renew DHCP on Devices**
   - Devices will get new DNS on next DHCP renewal
   - Or manually reconnect WiFi on each device

### B. Per-Device Configuration

If you can't modify router settings, configure each device individually.

#### Linux

**Temporary (for testing):**
```bash
# Test DNS query directly to Pi-hole
dig @192.168.2.50 coder.lab

# Set DNS for current session (Ubuntu/NetworkManager)
sudo resolvectl dns [interface] 192.168.2.50
sudo resolvectl domain [interface] ~lab
```

**Permanent (systemd-resolved):**
```bash
# Edit resolved.conf
sudo nano /etc/systemd/resolved.conf

# Add these lines:
# [Resolve]
# DNS=192.168.2.50 1.1.1.1
# Domains=~lab

sudo systemctl restart systemd-resolved
```

**Permanent (NetworkManager):**
```bash
# Edit connection
nmcli con mod "Your WiFi Name" ipv4.dns "192.168.2.50,1.1.1.1"
nmcli con mod "Your WiFi Name" ipv4.ignore-auto-dns yes
nmcli con down "Your WiFi Name" && nmcli con up "Your WiFi Name"
```

#### macOS

**Temporary (for testing):**
```bash
# Test DNS query
dig @192.168.2.50 coder.lab

# Set DNS temporarily
networksetup -setdnsservers Wi-Fi 192.168.2.50 1.1.1.1
```

**Permanent (GUI):**
1. Open **System Settings** → **Network**
2. Select your active connection (Wi-Fi or Ethernet)
3. Click **Details** (or **Advanced**)
4. Go to **DNS** tab
5. Remove all existing DNS servers
6. Click **+** and add: `192.168.2.50`
7. Click **+** and add: `1.1.1.1` (fallback)
8. Click **OK** → **Apply**

#### Windows

**Temporary (for testing):**
```powershell
# Test DNS query
nslookup coder.lab 192.168.2.50
```

**Permanent (GUI):**
1. Open **Settings** → **Network & Internet**
2. Click your connection (Wi-Fi or Ethernet)
3. Click **Edit** next to **DNS server assignment**
4. Select **Manual**
5. Enable **IPv4**
6. Preferred DNS: `192.168.2.50`
7. Alternate DNS: `1.1.1.1`
8. Click **Save**

**Permanent (PowerShell):**
```powershell
# List network adapters
Get-NetAdapter

# Set DNS (replace "Wi-Fi" with your adapter name)
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("192.168.2.50","1.1.1.1")
```

#### iOS/iPadOS

1. Open **Settings** → **Wi-Fi**
2. Tap the **(i)** next to your network
3. Scroll to **DNS**
4. Tap **Configure DNS** → **Manual**
5. Remove existing servers
6. Add **DNS Server**: `192.168.2.50`
7. Add **DNS Server**: `1.1.1.1` (fallback)
8. Tap **Save**

#### Android

1. Open **Settings** → **Network & Internet** → **Wi-Fi**
2. Long-press your network → **Modify Network**
3. Tap **Advanced Options**
4. Change **IP Settings** to **Static**
5. Set **DNS 1** to: `192.168.2.50`
6. Set **DNS 2** to: `1.1.1.1`
7. Keep other settings (IP, Gateway) unchanged
8. Tap **Save**

---

## Method 3: /etc/hosts (Testing/Fallback)

Add individual entries to your device's hosts file. This works without Pi-hole but requires updating every time you add a service.

### Linux/macOS

```bash
# Edit hosts file
sudo nano /etc/hosts

# Add these lines (replace 192.168.2.50 with your server IP)
192.168.2.50 home.lab
192.168.2.50 coder.lab
192.168.2.50 gitlab.lab
192.168.2.50 gitea.lab
192.168.2.50 n8n.lab
192.168.2.50 vaultwarden.lab
192.168.2.50 nextcloud.lab
192.168.2.50 paperless.lab
192.168.2.50 immich.lab
192.168.2.50 mealie.lab
192.168.2.50 vikunja.lab
192.168.2.50 firefly.lab
192.168.2.50 focalboard.lab
192.168.2.50 wger.lab
192.168.2.50 trilium.lab
192.168.2.50 hoarder.lab
192.168.2.50 navidrome.lab
192.168.2.50 kavita.lab
192.168.2.50 ollama.lab
192.168.2.50 open-webui.lab
192.168.2.50 librechat.lab
192.168.2.50 anythingllm.lab
192.168.2.50 searxng.lab
192.168.2.50 stable-diffusion.lab
192.168.2.50 comfyui.lab
192.168.2.50 localai.lab
192.168.2.50 privategpt.lab
192.168.2.50 nocodb.lab
192.168.2.50 homeassistant.lab
192.168.2.50 nodered.lab
192.168.2.50 grafana.lab
192.168.2.50 prometheus.lab
192.168.2.50 portainer.lab
192.168.2.50 dozzle.lab
192.168.2.50 uptime-kuma.lab
192.168.2.50 bytestash.lab
192.168.2.50 it-tools.lab
192.168.2.50 filebrowser.lab
192.168.2.50 postiz.lab
192.168.2.50 diffrhythm.lab
192.168.2.50 whisper.lab
192.168.2.50 whisperx.lab
192.168.2.50 resourcespace.lab

# Save and exit (Ctrl+X, Y, Enter in nano)
```

### Windows

1. Open **Notepad as Administrator**
   - Search for "Notepad" in Start Menu
   - Right-click → **Run as administrator**

2. **Open hosts file**
   - File → Open
   - Navigate to: `C:\Windows\System32\drivers\etc\`
   - Change filter to "All Files (*.*)"
   - Open the `hosts` file

3. **Add entries** (same format as above)
   ```
   192.168.2.50 home.lab
   192.168.2.50 coder.lab
   # ... etc
   ```

4. **Save and close**

### ⚠️ Limitations of /etc/hosts Method

- ❌ Must update manually when adding new services
- ❌ Must configure every device individually
- ❌ Doesn't work for mobile devices without root/jailbreak
- ❌ No wildcard support

**Recommendation:** Use this method only for quick testing. Switch to Method 1 or 2 for production use.

---

## Verification

After configuring DNS, verify it's working:

### 1. Run the Diagnostic Tool

```bash
cd /opt/stacks/weekendstack
bash tools/diagnose_lab.sh
```

**Expected Output:**
```
== Weekend Stack local (.lab) diagnostics ==
...
-- 3) DNS query directly against Pi-hole (192.168.2.50:53) --
192.168.2.50

-- 4) DNS query using system resolver --
192.168.2.50

-- 5) HTTP request to http://192.168.2.50 (bypassing DNS) --
HTTP/1.1 200 OK
```

### 2. Manual DNS Test

**Using dig (Linux/macOS):**
```bash
# Test against Pi-hole directly
dig @192.168.2.50 coder.lab
# Should return: 192.168.2.50

# Test using system DNS
dig coder.lab
# Should return: 192.168.2.50
```

**Using nslookup (Windows/all):**
```bash
# Test against Pi-hole directly
nslookup coder.lab 192.168.2.50
# Should return: Address: 192.168.2.50

# Test using system DNS
nslookup coder.lab
# Should return: Address: 192.168.2.50
```

### 3. Browser Test

Open your browser and visit:
- http://home.lab (Glance dashboard)
- http://coder.lab (Coder IDE)
- http://portainer.lab (Portainer)

**If browser loads the page:** ✅ DNS is working!

**If browser shows error:**
- "Cannot resolve host" → DNS not configured correctly
- "Connection refused" → DNS works but service is down
- "Certificate error" → DNS works but HTTPS cert needs trust (see HTTPS guide)

---

## Troubleshooting

### Issue: "Cannot resolve host" or "Server not found"

**Check system DNS settings:**
```bash
# Linux (systemd-resolved)
resolvectl status

# Linux (NetworkManager)
nmcli dev show | grep DNS

# macOS
scutil --dns | grep nameserver

# Windows
ipconfig /all | findstr "DNS Servers"
```

**Expected:** Should show `192.168.2.50` as a DNS server.

**Fix:** Reconfigure DNS using one of the methods above.

### Issue: DNS works for some domains but not .lab

**Check DNS server is Pi-hole:**
```bash
dig coder.lab
# Look at "SERVER: " line - should be 192.168.2.50:53
```

**If using different DNS:**
- Check if VPN is overriding DNS settings
- Check if browser is using DNS-over-HTTPS (disable in browser settings)
- On macOS, check if "Advanced Privacy Protection" is enabled in Safari

### Issue: DNS resolution is slow

**Possible causes:**
1. Pi-hole container not running: `docker compose ps pihole`
2. Upstream DNS slow: Check Pi-hole settings at http://192.168.2.50:8088/admin
3. DNSSEC validation failing: Disable in Pi-hole settings if needed

### Issue: Works on some devices but not others

Each device may have different DNS settings:
- Check each device's DNS configuration individually
- Router-level DNS (Method 1 or 2A) avoids this issue

### Issue: Works on WiFi but not Ethernet (or vice versa)

DNS settings are per-interface. Configure both:
```bash
# Linux
nmcli con mod "Wired connection 1" ipv4.dns "192.168.2.50,1.1.1.1"
nmcli con mod "WiFi Name" ipv4.dns "192.168.2.50,1.1.1.1"
```

---

## Next Steps

After DNS is working:

1. **Enable HTTPS (Optional):**
   - See [docs/local-https-setup.md](local-https-setup.md)
   - Generates TLS certificates for `https://` access
   - Requires trusting a local CA certificate

2. **Access Services:**
   - Visit http://home.lab for the Glance dashboard
   - Browse to any service at `http://[service].lab`
   - See [README.md](../README.md) for full service list

3. **Monitor DNS:**
   - Pi-hole admin: http://192.168.2.50:8088/admin
   - View query logs, blocked domains, and statistics

---

## Summary

| Method | Scope | Wildcard | Difficulty | Recommended For |
|--------|-------|----------|------------|-----------------|
| **Router DNS** | Network-wide | ✅ Yes | Medium | UniFi, pfSense, DD-WRT users |
| **Pi-hole (Router DHCP)** | Network-wide | ✅ Yes | Easy | Users who can modify router DHCP |
| **Pi-hole (Per-Device)** | Per-device | ✅ Yes | Easy-Medium | Users without router access |
| **/etc/hosts** | Per-device | ❌ No | Easy | Testing/temporary use only |

**Best Practice:** Use router-level DNS (Method 1 or 2A) for automatic configuration across all devices. This ensures phones, tablets, and any device on your network can access `.lab` services without individual setup.
