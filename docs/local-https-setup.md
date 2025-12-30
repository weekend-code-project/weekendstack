# Local HTTPS Setup for .lab Domains

This guide explains how to enable HTTPS for all your local `.lab` domains without browser security warnings.

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
- `ca-cert.pem` - Certificate Authority certificate (needed for trusting)
- `ca-key.pem` - CA private key (keep secure!)
- `cert.pem` - Wildcard certificate for `*.lab`
- `key.pem` - Server private key

### 2. Trust the Certificate Authority

Choose the appropriate method for your operating system:

#### Linux (Ubuntu/Debian)

```bash
# Copy CA certificate to system trust store
sudo cp config/traefik/certs/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt

# Update CA certificates
sudo update-ca-certificates
```

#### Linux (Fedora/RHEL/CentOS)

```bash
# Copy CA certificate to system trust store
sudo cp config/traefik/certs/ca-cert.pem /etc/pki/ca-trust/source/anchors/weekendstack-ca.crt

# Update CA certificates
sudo update-ca-trust
```

#### macOS

```bash
# Add certificate to system keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  config/traefik/certs/ca-cert.pem
```

#### Windows

1. Double-click `config\traefik\certs\ca-cert.pem`
2. Click "Install Certificate"
3. Select "Local Machine"
4. Select "Place all certificates in the following store"
5. Click "Browse" and select "Trusted Root Certification Authorities"
6. Click "Next" and "Finish"

#### Firefox (All Platforms)

Firefox uses its own certificate store and ignores system certificates:

1. Open Firefox Settings
2. Navigate to **Privacy & Security**
3. Scroll down to **Certificates**
4. Click **View Certificates**
5. Go to **Authorities** tab
6. Click **Import**
7. Select `config/traefik/certs/ca-cert.pem`
8. Check **Trust this CA to identify websites**
9. Click **OK**

### 3. Restart Traefik

After trusting the CA certificate, restart Traefik to load the certificates:

```bash
docker compose restart traefik
```

### 4. Access Services via HTTPS

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
