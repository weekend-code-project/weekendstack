# Cloudflare Tunnel Setup

This directory contains the configuration for Cloudflare Tunnel, which provides secure external access to your services without exposing ports or requiring a public IP address.

## Prerequisites

- A Cloudflare account with a domain added
- One of the following:
  - **Method 1 (Recommended)**: Cloudflare API token
  - **Method 2**: `cloudflared` CLI tool installed
  - **Method 3**: Manual tunnel creation

## Quick Start (Recommended: API Method)

The easiest way to set up Cloudflare Tunnel is using the automated API method:

1. **Create an API token** at https://dash.cloudflare.com/profile/api-tokens
   - Click "Create Token" → "Create Custom Token"
   - Permissions needed:
     - Account - Cloudflare Tunnel - Edit
     - Zone - DNS - Edit
   - Zone Resources: Include - Specific zone - [your-domain.com]

2. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

3. **Select Cloudflare Tunnel setup when prompted**
   - Choose "API (Recommended)" method
   - Enter your API token
   - The script will automatically:
     - Create the tunnel
     - Generate credentials
     - Configure DNS records
     - Create config.yml

That's it! The tunnel will be fully configured and ready to start.

## Setup Methods

### Method 1: API (Recommended) - Fully Automated

**Advantages:**
- Fully automated - no manual steps
- Works without installing cloudflared locally
- Ideal for headless servers
- Can reuse existing tunnels

**Steps:**
1. Create API token (see Quick Start above)
2. Run `./setup.sh` and select API method
3. Enter API token when prompted
4. Script handles everything automatically

The setup wizard will:
- Validate your API token
- Check for existing tunnels (or create new one)
- Generate credentials JSON file
- Create wildcard DNS record
- Generate config.yml

### Method 2: CLI - Semi-Automated

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

### Method 2: CLI - Semi-Automated

**Advantages:**
- Interactive browser authentication
- Local credential management
- Good for desktop/laptop setups

**Requirements:**
```bash
# Linux/macOS
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Or use package manager
brew install cloudflared  # macOS
```

**Steps:**

**Steps:**

#### 1. Authenticate with Cloudflare
```bash
cloudflared tunnel login
```
This will open a browser window to authorize access to your Cloudflare account.

#### 2. Create a Tunnel
```bash
cloudflared tunnel create weekendstack
```
This creates:
- A tunnel with the name `weekendstack`
- A credentials file with a UUID (e.g., `YOUR-TUNNEL-UUID.json`)

**Important:** Copy the tunnel UUID from the output - you'll need it for the config file.

#### 3. Run setup script
```bash
./setup.sh
```
Select "CLI" method and the script will:
- Detect your existing tunnel
- Copy credentials to the correct location
- Create config.yml
- Set up DNS records

### Method 3: Manual - Full Control

**Advantages:**
- Complete control over each step
- Good for understanding the process
- Useful when automation isn't available

**Steps:**

#### 1. Create tunnel in Cloudflare Dashboard
1. Go to https://one.dash.cloudflare.com/
2. Navigate to: Networks > Tunnels
3. Click "Create a tunnel"
4. Choose "Cloudflared" as connector
5. Name your tunnel (e.g., `weekendstack-tunnel`)
6. **Important:** Copy the Tunnel ID (UUID)

#### 2. Download credentials
- Download the JSON credentials file from the dashboard
- Or copy the credentials JSON content

#### 3. Run setup script
```bash
./setup.sh
```

#### 3. Run setup script
```bash
./setup.sh
```
Select "Manual" method and provide:
- Tunnel name
- Tunnel ID (UUID from step 1)
- Credentials (file path or paste JSON)

The script will:
- Save credentials to config/cloudflare/
- Create config.yml
- Prompt you to create DNS records manually

#### 4. Create DNS record manually
In Cloudflare Dashboard → DNS:
- **Type:** CNAME
- **Name:** `*` (for wildcard)
- **Target:** `<TUNNEL-UUID>.cfargotunnel.com`
- **Proxy status:** Proxied (orange cloud)

## Starting the Tunnel

After setup (any method), start the tunnel:

```bash
# Start all services including tunnel
docker compose --profile networking up -d

# Or start just the tunnel
docker compose up -d cloudflare-tunnel
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

**Tunnel not connecting**
- Verify credentials file exists in `config/cloudflare/`
- Check the UUID in `config.yml` matches your credentials file
- Ensure DNS records are properly configured in Cloudflare

**Services returning 404**
- Verify Traefik is running: `docker compose ps traefik`
- Check Traefik logs: `docker compose logs traefik`
- Ensure service labels include correct domain names

**SSL/TLS errors**
- The `noTLSVerify: true` setting is intentional for self-signed certificates
- Cloudflare handles SSL/TLS to the internet
- Internal traffic uses Traefik's self-signed certificates

## Configuration Files

After setup, you'll have:

```
config/cloudflare/
├── config.yml                    # Tunnel ingress rules
├── <tunnel-uuid>.json            # Credentials (generated by API or CLI)
└── README.md                     # This file
```

**config.yml** format:
```yaml
tunnel: your-tunnel-name
credentials-file: /etc/cloudflared/.cloudflared/<tunnel-uuid>.json

ingress:
  - hostname: "*.yourdomain.com"
    service: https://traefik:443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

## Additional Resources

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Tunnel Configuration Reference](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/)
- [API Documentation](https://developers.cloudflare.com/api/operations/cloudflare-tunnel-create-a-cloudflare-tunnel)

## Security Notes

- **Never commit** sensitive files to git:
  - `config.yml`
  - `*.json` (credentials files)
  - `.env` (contains API token)
- The `.gitignore` is already configured to exclude these
- **API Tokens**: Store securely, grant minimal permissions, rotate regularly
- **Credentials**: Each user should create their own tunnel and credentials
- **Scope API tokens** to specific zones and minimal permissions needed

## Troubleshooting

### API Method Issues

**"API token is invalid"**
- Verify token has required permissions:
  - Account - Cloudflare Tunnel - Edit
  - Zone - DNS - Edit (for your domain)
- Token must not be expired
- Create new token at: https://dash.cloudflare.com/profile/api-tokens

**"Zone not found for domain"**
- Ensure domain is added to your Cloudflare account
- Verify you're using the root domain (example.com not subdomain.example.com)
- Check token has access to the correct zone

**"Tunnel already exists"**
- Setup wizard will offer to use existing tunnel
- Or manually delete old tunnel in dashboard
- Or choose a different tunnel name

### CLI/Manual Method Issues

### Tunnel not connecting
