# Cloudflare Tunnel - API Automated Setup Guide

This guide explains how to use the Cloudflare API for fully automated tunnel setup. This is the **recommended method** for WeekendStack as it requires no manual steps and works headlessly.

## Overview

The API method uses Cloudflare's REST API to:
- ✅ Create tunnels programmatically
- ✅ Generate credentials automatically
- ✅ Configure DNS records
- ✅ Support existing tunnels (idempotent)
- ✅ No `cloudflared` CLI installation required
- ✅ Perfect for servers and automation

## Prerequisites

1. **Cloudflare Account** (free tier works fine)
2. **Domain added to Cloudflare** (nameservers pointed to Cloudflare)
3. **API Token** with correct permissions (we'll create this below)

## Step 1: Create API Token

### Via Cloudflare Dashboard

1. Log in to https://dash.cloudflare.com/
2. Click on your profile icon (top right) → **My Profile**
3. Select **API Tokens** from left menu
4. Click **Create Token**
5. Click **Create Custom Token**

### Configure Token Permissions

Set these permissions:

| Permission | Zone/Account | Access Level |
|------------|--------------|--------------|
| Cloudflare Tunnel | Account | Edit |
| DNS | Zone | Edit |

### Configure Zone Resources

Under "Zone Resources":
- **Include** → **Specific zone** → Select your domain (e.g., `example.com`)

### Set Token Expiry (Optional but Recommended)

- **TTL**: Set an expiration date (e.g., 1 year)
- You can always create a new token later

### Create and Copy Token

1. Click **Continue to summary**
2. Review permissions
3. Click **Create Token**
4. **IMPORTANT**: Copy the token now - it's only shown once!
5. Store it securely (password manager, .env file)

Example token format: `xTj8F9sk3_AbCdEfGhIjKlMnOpQrStUvWxYz`

## Step 2: Run Setup Script

### Interactive Setup

```bash
./setup.sh
```

When prompted:
1. Select the `networking` profile (or any profile with Cloudflare)
2. When asked about Cloudflare Tunnel, select **Yes**
3. Choose **API (Recommended)** method
4. Enter your API token when prompted
5. Enter your domain name (e.g., `example.com`)
6. Choose or confirm tunnel name (e.g., `weekendstack-tunnel`)

The script will:
- ✅ Validate your API token
- ✅ Check for existing tunnels
- ✅ Create new tunnel (or use existing)
- ✅ Generate credentials JSON
- ✅ Create `config/cloudflare/config.yml`
- ✅ Set up wildcard DNS: `*.example.com`
- ✅ Update `.env` with tunnel details

### What Gets Created

After successful setup:

```
config/cloudflare/
├── config.yml                          # Tunnel configuration
└── <tunnel-uuid>.json                  # Credentials file

.env (updated with):
├── CLOUDFLARE_API_TOKEN=...            # Your API token
├── CLOUDFLARE_ACCOUNT_ID=...           # Auto-detected
├── CLOUDFLARE_TUNNEL_ENABLED=true
├── CLOUDFLARE_TUNNEL_NAME=...
└── CLOUDFLARE_TUNNEL_ID=...
```

## Step 3: Start Services

```bash
# Start all services including Cloudflare tunnel
docker compose --profile networking up -d

# Or start just the tunnel
docker compose up -d cloudflare-tunnel
```

## Step 4: Verify Tunnel

Check tunnel is connected:
```bash
docker logs cloudflare-tunnel
```

Expected output:
```
INFO Connection registered connIndex=0
INFO Registered tunnel connection
```

Test external access:
```bash
curl https://home.example.com
# Should return your Glance dashboard (or Traefik page)
```

## Troubleshooting

### "API token is invalid"

**Cause**: Token doesn't have required permissions or is expired

**Solution**:
1. Create new token with correct permissions (see Step 1)
2. Update `.env`:
   ```bash
   CLOUDFLARE_API_TOKEN=your-new-token
   ```
3. Re-run setup: `./setup.sh --reconfigure`

### "Zone not found for domain"

**Cause**: Domain not in your Cloudflare account, or token lacks access

**Solution**:
1. Verify domain is added to Cloudflare: https://dash.cloudflare.com/
2. Ensure nameservers point to Cloudflare
3. Check token permissions include your zone
4. Use root domain (e.g., `example.com` not `sub.example.com`)

### "Tunnel already exists"

**Cause**: You previously created a tunnel with this name

**Solution**:
- Setup wizard will ask if you want to use existing tunnel → Select **Yes**
- Or delete old tunnel in dashboard: https://one.dash.cloudflare.com/
- Or choose a different tunnel name

### DNS not resolving

**Cause**: DNS record not created or not yet propagated

**Verification**:
```bash
dig *.example.com
# Should show CNAME to <tunnel-id>.cfargotunnel.com
```

**Solution**:
1. Check DNS in dashboard: https://dash.cloudflare.com/ → DNS
2. Manually create CNAME if missing:
   - Type: CNAME
   - Name: `*`
   - Target: `<tunnel-id>.cfargotunnel.com`
   - Proxied: Yes (orange cloud)
3. Wait for propagation (usually seconds, max 5 minutes)

### Services return 404

**Cause**: Traefik not running or misconfigured

**Solution**:
```bash
# Check Traefik is running
docker compose ps traefik

# Check Traefik logs
docker compose logs traefik

# Restart Traefik
docker compose restart traefik
```

## Advanced: Reusing Existing Tunnels

If you already have a tunnel created manually, the API setup can detect and use it:

1. Run `./setup.sh`
2. Select API method
3. When asked about existing tunnel → Select **Yes**
4. Script will retrieve existing credentials and configure everything

## API Token Security Best Practices

### Do's ✅
- Store token in `.env` (gitignored)
- Use minimal required permissions
- Set expiration dates
- Rotate tokens regularly (annually)
- Create separate tokens for different environments (dev/prod)

### Don'ts ❌
- Don't commit tokens to git
- Don't grant "All zones" access (scope to specific zone)
- Don't use Account API keys (use tokens instead)
- Don't share tokens between users
- Don't store in plain text outside .env

### Revoking Tokens

If compromised:
1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Find the token
3. Click **Roll** or **Delete**
4. Create new token
5. Update `.env`
6. Re-run setup if needed

## Comparison with Other Methods

| Feature | API Method | CLI Method | Manual Method |
|---------|-----------|------------|---------------|
| **Automation** | Full | Partial | None |
| **CLI Required** | No | Yes | No |
| **Headless Support** | Yes | Limited | Yes |
| **Browser Auth** | No | Yes | Yes |
| **Idempotent** | Yes | No | No |
| **Best For** | Servers, automation | Desktop setup | Learning, troubleshooting |

## Related Documentation

- [Cloudflare Tunnel Setup](../config/cloudflare/README.md) - All setup methods
- [Setup Script Guide](setup-script-guide.md) - Full setup walkthrough
- [Cloudflare API Reference](https://developers.cloudflare.com/api/operations/cloudflare-tunnel-create-a-cloudflare-tunnel)
- [API Token Permissions](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
