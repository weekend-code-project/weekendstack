# Local HTTPS Setup for .lab Domains

This guide explains how to enable HTTPS for all your local `.lab` domains without browser security warnings.

## Prerequisites

**⚠️ DNS must be configured first!** HTTPS won't work if your browser can't resolve `.lab` domains.

- ✅ DNS configured: See [dns-setup-guide.md](dns-setup-guide.md)
- ✅ Services accessible via HTTP: Visit http://home.lab to verify
- ✅ Pi-hole and Traefik running: `docker compose ps pihole traefik`

If you haven't configured DNS yet, **stop here** and follow [dns-setup-guide.md](dns-setup-guide.md) first.

---

## Overview

The Weekend Stack includes an automated certificate generation system that creates:
- A local Certificate Authority (CA)
- A wildcard SSL certificate for `*.lab` domains

After certificates are generated, you need to trust the CA certificate in your system/browser (one-time manual step).

## Quick Start

### 1. Generate Certificates

Certificates are automatically generated when you start the networking services:

```bash
docker compose up cert-generator
```

Or they're created automatically when you start all services:

```bash
docker compose --profile all up -d
```

The certificate files are saved to `./config/traefik/certs/`:
- `ca-cert.pem` - Certificate Authority certificate **(you'll need this file)**
- `ca-key.pem` - CA private key (keep secure!)
- `cert.pem` - Wildcard certificate for `*.lab`
- `key.pem` - Server private key

### 2. Trust the Certificate Authority

**Important:** You must perform this step on **each device** where you want to access services via HTTPS (laptop, desktop, phone, etc.).

Choose the appropriate method for your operating system:

#### Linux (Ubuntu/Debian)

**Method 1: Using the Command Line (Recommended)**

```bash
# Navigate to the weekendstack directory
cd /opt/stacks/weekendstack

# Copy CA certificate to system trust store
sudo cp config/traefik/certs/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt

# Update CA certificates
sudo update-ca-certificates

# Verify installation
ls -la /usr/local/share/ca-certificates/weekendstack-ca.crt
```

**Expected Output:**
```
Updating certificates in /etc/ssl/certs...
1 added, 0 removed; done.
```

**Method 2: If you need the file on another Linux machine**

1. Copy the CA certificate to the target machine:
   ```bash
   # From the server
   scp config/traefik/certs/ca-cert.pem user@target-machine:~/

   # On the target machine
   sudo cp ~/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt
   sudo update-ca-certificates
   ```

#### Linux (Fedora/RHEL/CentOS)

```bash
# Navigate to the weekendstack directory
cd /opt/stacks/weekendstack

# Copy CA certificate to system trust store
sudo cp config/traefik/certs/ca-cert.pem /etc/pki/ca-trust/source/anchors/weekendstack-ca.crt

# Update CA certificates
sudo update-ca-trust

# Verify installation
ls -la /etc/pki/ca-trust/source/anchors/weekendstack-ca.crt
```

#### Linux (Arch/Manjaro)

```bash
# Navigate to the weekendstack directory
cd /opt/stacks/weekendstack

# Copy CA certificate to system trust store
sudo cp config/traefik/certs/ca-cert.pem /etc/ca-certificates/trust-source/anchors/weekendstack-ca.crt

# Update CA certificates
sudo trust extract-compat

# Verify installation
ls -la /etc/ca-certificates/trust-source/anchors/weekendstack-ca.crt
```

#### macOS

**Method 1: Using Command Line (Recommended)**

```bash
# Navigate to the weekendstack directory
cd /opt/stacks/weekendstack

# Add certificate to system keychain and mark as trusted
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  config/traefik/certs/ca-cert.pem

# Verify it was added
security find-certificate -c "Weekend Stack Local CA" /Library/Keychains/System.keychain
```

**Method 2: Using Keychain Access GUI**

1. Open **Finder** → Navigate to `weekendstack/config/traefik/certs/`
2. Double-click `ca-cert.pem`
3. In **Keychain Access**, select **System** keychain
4. Click **Add**
5. Find the certificate (search for "Weekend Stack Local CA")
6. Double-click the certificate
7. Expand **Trust**
8. Set **When using this certificate** to **Always Trust**
9. Close the window and enter your password

**Method 3: If you need the file on another Mac**

1. Copy the CA certificate file to the target Mac (via AirDrop, USB, or scp)
2. Follow Method 1 or Method 2 on the target Mac

#### Windows

**Method 1: Using Certificate Manager (Recommended)**

1. Copy the file `config\traefik\certs\ca-cert.pem` to your Windows machine
2. Right-click `ca-cert.pem` → **Install Certificate**
3. Select **Local Machine** → Click **Next**
4. Select **Place all certificates in the following store**
5. Click **Browse** → Select **Trusted Root Certification Authorities**
6. Click **Next** → **Finish**
7. Click **Yes** on the security warning

**Method 2: Using PowerShell (Advanced)**

```powershell
# Import the certificate (run as Administrator)
Import-Certificate -FilePath "\\server\share\ca-cert.pem" `
  -CertStoreLocation Cert:\LocalMachine\Root

# Verify installation
Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*Weekend Stack*"}
```

**Method 3: Using certutil (Command Line)**

```cmd
REM Run Command Prompt as Administrator
certutil -addstore "Root" "C:\path\to\ca-cert.pem"

REM Verify installation
certutil -store "Root" | findstr "Weekend Stack"
```

#### iOS/iPadOS

**Transfer the Certificate:**

Option A: Email
1. Email `config/traefik/certs/ca-cert.pem` to yourself
2. Open the email on your iOS device
3. Tap the attachment

Option B: AirDrop
1. AirDrop `ca-cert.pem` from your Mac to your iOS device

Option C: Host via web server
1. On your server: `cd config/traefik/certs && python3 -m http.server 8999`
2. On iOS Safari, visit: `http://192.168.2.50:8999/ca-cert.pem`

**Install the Certificate:**

1. After opening the file, tap **Allow** to download the profile
2. Go to **Settings** → **General** → **VPN & Device Management**
3. Under **Downloaded Profile**, tap **Weekend Stack Local CA**
4. Tap **Install** (top right)
5. Enter your passcode
6. Tap **Install** again (confirmation)
7. Tap **Done**

**Enable Full Trust:**

1. Go to **Settings** → **General** → **About** → **Certificate Trust Settings**
2. Find **Weekend Stack Local CA**
3. Toggle the switch to **ON** (green)
4. Tap **Continue** on the warning

#### Android

**Transfer the Certificate:**

Option A: Email/File Share
1. Email or share `config/traefik/certs/ca-cert.pem` to your Android device
2. Download the file

Option B: Host via web server
1. On your server: `cd config/traefik/certs && python3 -m http.server 8999`
2. On Android Chrome, visit: `http://192.168.2.50:8999/ca-cert.pem`

**Install the Certificate:**

1. Open **Settings** → **Security** (or **Biometrics and Security**)
2. Scroll to **Encryption & Credentials** (or **Credential Storage**)
3. Tap **Install a certificate** (or **Install from device storage**)
4. Select **CA certificate**
5. Tap **Install anyway** on the warning
6. Navigate to where you downloaded `ca-cert.pem`
7. Select the file
8. Enter a name: "Weekend Stack CA"

**Note:** On Android 11+, user-installed CA certificates may not work for all apps. System apps and Chrome will respect them, but some apps may not.

#### Firefox (All Platforms)

Firefox uses its own certificate store and **ignores system certificates**. You must configure Firefox separately even if you've already installed the certificate in your OS.

**Installation Steps:**

1. Open Firefox
2. Click menu (☰) → **Settings** (or **Preferences**)
3. Navigate to **Privacy & Security**
4. Scroll down to **Certificates**
5. Click **View Certificates**
6. Go to **Authorities** tab
7. Click **Import...**
8. Navigate to `config/traefik/certs/` and select `ca-cert.pem`
   - On remote machines, copy the file first or use the web server method above
9. Check **☑ Trust this CA to identify websites**
10. Click **OK**
11. Close the Certificate Manager

**Verification:**
1. Visit `https://home.lab`
2. Click the padlock icon → **Connection secure**
3. Should show "Weekend Stack Local CA"

#### Chrome/Edge (If System Trust Doesn't Work)

Usually, Chrome and Edge use the system certificate store, but if you still see warnings:

**Windows/Linux Chrome:**
1. Visit `chrome://settings/certificates`
2. Go to **Authorities** tab
3. Click **Import**
4. Select `ca-cert.pem`
5. Check **Trust this certificate for identifying websites**
6. Click **OK**

**macOS Chrome:**
- Chrome uses the macOS Keychain, so ensure you followed the macOS steps above
- Restart Chrome after installing the certificate

### 3. Restart Browsers (Important!)

After installing the certificate, **restart all browsers** for changes to take effect:

```bash
# Close and reopen:
# - Chrome/Chromium
# - Firefox  
# - Safari
# - Edge
```

On mobile devices, you may need to force-close the browser app.

After trusting the CA certificate, restart Traefik to load the certificates:

```bash
docker compose restart traefik
```

On mobile devices, you may need to force-close the browser app.

### 4. Verify HTTPS is Working

**Browser Test:**

Visit any `.lab` domain with HTTPS:
```
https://home.lab
https://coder.lab
https://portainer.lab
```

**Expected Result:**
- ✅ Page loads without warnings
- ✅ Green padlock icon in address bar
- ✅ Click padlock → Shows "Connection is secure"
- ✅ Certificate details show "Weekend Stack Local CA"

**Common Issues:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Your connection is not private" warning | CA not trusted | Re-check installation steps for your OS |
| "NET::ERR_CERT_AUTHORITY_INVALID" | Certificate not in system store | Verify file was copied correctly |
| Warning only in Firefox | Firefox needs separate import | Follow Firefox-specific steps |
| Works on desktop, fails on phone | Certificate not installed on phone | Install CA on mobile device |
| "Cannot connect" or "DNS not found" | DNS not configured | **DNS must work first!** See [dns-setup-guide.md](dns-setup-guide.md) |

### 5. Access Services via HTTPS

All `.lab` domains now support both HTTP and HTTPS:

- **HTTP**: `http://service.lab` (still works, backward compatible)
- **HTTPS**: `https://service.lab` (now available with no warnings!)

Examples:
- `https://coder.lab`
- `https://gitea.lab`
- `https://home.lab` (Glance dashboard)
- `https://nocodb.lab`

## Verification

### Check Certificate Trust

Visit any `.lab` domain with HTTPS in your browser:

```
https://home.lab
```

**Expected Result**: No security warnings, valid green padlock icon

**If you see warnings**: The CA certificate hasn't been properly installed or trusted.

### Test Certificate Details

Check certificate information:

```bash
# View certificate
openssl x509 -in config/traefik/certs/cert.pem -text -noout

# Verify certificate chain
openssl verify -CAfile config/traefik/certs/ca-cert.pem config/traefik/certs/cert.pem
```

## Certificate Details

### Validity Period

- **CA Certificate**: 10 years (3650 days)
- **Wildcard Certificate**: 825 days (Chrome/Safari requirement)

### Renewal

Certificates are valid for 2+ years. To regenerate (after expiry or if compromised):

```bash
# Delete existing certificates
rm config/traefik/certs/*.pem

# Regenerate
docker compose up cert-generator

# Re-trust the NEW CA certificate (repeat Step 2 above)
# Restart Traefik
docker compose restart traefik
```

**Important**: After regenerating, you must re-trust the new CA certificate!

## Troubleshooting

### Browser Still Shows Warnings

**Possible causes:**
1. CA certificate not installed in system/browser trust store
2. Browser cache - try hard refresh (Ctrl+F5) or restart browser
3. Certificate files missing or corrupted
4. Traefik hasn't loaded the certificates

**Solutions:**
- Verify CA certificate installation (see Step 2)
- Clear browser cache and restart
- Check certificate files exist in `./config/traefik/certs/`
- Check Traefik logs: `docker compose logs traefik`

### Certificate Name Mismatch

If accessing via IP address (`https://192.168.2.50`), you'll see a warning because the certificate is only for `*.lab` domains.

**Solution**: Always use `.lab` domain names for HTTPS access.

### Firefox Specific Issues

Firefox uses its own certificate store, separate from the system.

**Solution**: Import the CA certificate directly in Firefox (see Firefox section above).

### Services Not Loading Over HTTPS

Some services may require additional configuration for HTTPS.

**Check:**
1. Service has `websecure` entrypoint in Traefik labels
2. Service responds to HTTPS requests
3. Traefik logs for errors: `docker compose logs traefik`

## Security Considerations

### Private Key Security

The CA private key (`ca-key.pem`) should be kept secure:
- Never commit to public repositories (already in `.gitignore`)
- Restrict file permissions: `chmod 600 config/traefik/certs/ca-key.pem`
- Only valid for `.lab` domains (not internet-wide)

### Scope of Trust

This CA is only trusted on systems where you manually install it. It cannot be used to intercept traffic on other systems or the internet.

### Local Network Only

These certificates only work for `.lab` domains on your local network. External access via `weekendcodeproject.dev` uses Cloudflare's certificates.

## Environment Variables

Customize certificate generation in `.env`:

```bash
# Certificate validity (days)
CERT_VALID_DAYS=825         # Wildcard cert (default: 825, max for Chrome)
CA_VALID_DAYS=3650          # CA cert (default: 3650 = 10 years)

# Domain for local access
LAB_DOMAIN=lab              # Default: lab
```

## Advanced: Manual Certificate Generation

If you prefer to generate certificates manually:

```bash
# Create certs directory
mkdir -p config/traefik/certs
cd config/traefik/certs

# Generate CA private key
openssl genrsa -out ca-key.pem 4096

# Generate CA certificate
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/C=US/ST=Local/L=Local/O=Weekend Stack/OU=IT/CN=Weekend Stack Local CA"

# Generate server private key
openssl genrsa -out key.pem 4096

# Generate CSR
openssl req -new -key key.pem -out cert.csr \
  -subj "/C=US/ST=Local/L=Local/O=Weekend Stack/OU=IT/CN=*.lab"

# Create SAN config
cat > san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.lab
DNS.2 = lab
EOF

# Generate certificate
openssl x509 -req -in cert.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out cert.pem -days 825 -extensions v3_req -extfile san.cnf

# Clean up
rm cert.csr san.cnf ca-cert.srl

# Set permissions
chmod 600 ca-key.pem key.pem
chmod 644 ca-cert.pem cert.pem
```

## Related Documentation

- [Traefik Setup](traefik-setup.md) - Traefik reverse proxy configuration
- [Network Architecture](network-architecture.md) - Overall network design
- [Local Access Setup](local-access-setup.md) - Configuring .lab domains

## Support

If you encounter issues:
1. Check Traefik logs: `docker compose logs traefik`
2. Verify certificate files: `ls -la config/traefik/certs/`
3. Test certificate: `openssl verify -CAfile config/traefik/certs/ca-cert.pem config/traefik/certs/cert.pem`
4. Review this documentation
5. Create a GitHub issue with details
