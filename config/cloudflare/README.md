# Cloudflare Tunnel Setup

This directory contains the configuration for Cloudflare Tunnel, which provides secure external access to your services without exposing ports or requiring a public IP address.

## Prerequisites

- A Cloudflare account with a domain added
- `cloudflared` CLI tool installed

## Installation

### Linux/macOS
```bash
# Download and install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Or use package manager
brew install cloudflared  # macOS
```

### Windows
Download from: https://github.com/cloudflare/cloudflared/releases

## Setup Steps

### 1. Authenticate with Cloudflare
```bash
cloudflared tunnel login
```
This will open a browser window to authorize access to your Cloudflare account.

### 2. Create a Tunnel
```bash
cloudflared tunnel create weekendstack
```
This creates:
- A tunnel with the name `weekendstack`
- A credentials file with a UUID (e.g., `30b7532b-ad2e-4474-bd2a-ddd07fabac80.json`)

**Important:** Copy the tunnel UUID from the output - you'll need it for the config file.

### 3. Create Configuration File
```bash
# Copy the example config
cp config.yml.example config.yml
```

Edit `config.yml` and update:
- `tunnel:` - Your tunnel name (e.g., `weekendstack`)
- `credentials-file:` - Replace `YOUR-TUNNEL-UUID` with the UUID from step 2
- `hostname:` - Replace `example.com` with your actual domain

Example:
```yaml
tunnel: weekendstack
credentials-file: /etc/cloudflared/.cloudflared/30b7532b-ad2e-4474-bd2a-ddd07fabac80.json

ingress:
  - hostname: "*.yourdomain.com"
    service: https://traefik:443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

### 4. Copy Credentials to Docker Mount
```bash
# Create the credentials directory
mkdir -p .cloudflared

# Copy your credentials file (replace UUID with your actual UUID)
cp ~/.cloudflared/30b7532b-ad2e-4474-bd2a-ddd07fabac80.json .cloudflared/
```

### 5. Create DNS Records
For each subdomain you want to expose, create a CNAME record in Cloudflare:

```bash
cloudflared tunnel route dns weekendstack coder.yourdomain.com
cloudflared tunnel route dns weekendstack gitea.yourdomain.com
cloudflared tunnel route dns weekendstack '*.yourdomain.com'
```

Or manually in Cloudflare Dashboard:
- **Type:** CNAME
- **Name:** `*` (for wildcard) or specific subdomain
- **Target:** `<TUNNEL-UUID>.cfargotunnel.com`
- **Proxy status:** Proxied (orange cloud)

### 6. Update Environment Variables
In your `.env` file, set:
```bash
BASE_DOMAIN=yourdomain.com
```

### 7. Start the Stack
```bash
docker compose up -d
```

## Verify Setup

Check tunnel status:
```bash
docker compose logs cloudflare-tunnel
```

You should see:
```
INF Connection established connIndex=0
INF Registered tunnel connection
```

## Troubleshooting

### Tunnel not connecting
- Verify credentials file exists in `config/cloudflare/.cloudflared/`
- Check the UUID in `config.yml` matches your credentials file
- Ensure DNS records are properly configured in Cloudflare

### Services returning 404
- Verify Traefik is running: `docker compose ps traefik`
- Check Traefik logs: `docker compose logs traefik`
- Ensure service labels include correct domain names

### SSL/TLS errors
- The `noTLSVerify: true` setting is intentional for self-signed certificates
- Cloudflare handles SSL/TLS to the internet
- Internal traffic uses Traefik's self-signed certificates

## Security Notes

- **Never commit** `config.yml` or `.cloudflared/` directory to git
- These files contain your tunnel credentials
- The `.gitignore` is already configured to exclude them
- Each user should create their own tunnel and credentials

## Additional Resources

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Tunnel Configuration Reference](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/)
