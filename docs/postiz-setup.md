# Postiz Setup Guide

Postiz (formerly Gitroom) is a self-hosted social media management platform that allows you to schedule and manage posts across multiple social media platforms from a single interface.

## Overview

**URL:** https://postiz.weekendcodeproject.dev  
**Container:** `postiz`  
**Database:** PostgreSQL (`postiz-db`)  
**Cache:** Redis (`postiz-redis`)

## Architecture

Postiz runs as a multi-service container with an internal Nginx reverse proxy:

```
Traefik (HTTPS) → Postiz Container (Port 5000) → Nginx
                                                   ├─→ Frontend (Next.js on port 4200)
                                                   └─→ Backend API (NestJS on port 3000)
```

- **Frontend:** Next.js application for the user interface
- **Backend:** NestJS API for business logic and integrations
- **Nginx:** Internal routing between frontend and backend
  - `/api/*` routes to backend (port 3000)
  - Everything else routes to frontend (port 4200)

## Initial Setup

### 1. First Login

Visit https://postiz.weekendcodeproject.dev and create your account:

1. Click "Sign Up"
2. Enter your email, password, and company name
3. The first account created becomes the admin

**Note:** The `ADMIN_EMAIL` and `ADMIN_PASSWORD` environment variables in docker-compose are not used for auto-provisioning. You must manually register through the UI.

### 2. Email/Password Login

You can always log in using email and password without any OAuth configuration. OAuth is optional and only needed if you want:
- Social login (sign in with GitHub, Google, etc.)
- To connect social media accounts for posting

## Connecting Social Media Accounts

Postiz supports posting to 20+ platforms. You'll need to connect each platform you want to use for scheduling posts.

### Supported Platforms

#### Social Networks
- **X (Twitter)** - Tweet scheduling and management
- **LinkedIn** - Personal profile and company page posts
- **Instagram** - Photos, stories (requires Facebook Business account)
- **Facebook Page** - Page posts and scheduling
- **Threads** - Instagram's text-based platform
- **TikTok** - Video scheduling
- **Mastodon** - Decentralized social network

#### Content & Community Platforms
- **Reddit** - Community posts
- **YouTube** - Video publishing
- **Pinterest** - Pin scheduling
- **Discord** - Server announcements
- **Slack** - Team notifications

#### Developer & Professional Platforms
- **Dev.to** - Developer blog posts
- **Hashnode** - Developer blogging
- **Medium** - Article publishing
- **Dribbble** - Design showcases

#### Emerging Platforms
- **Bluesky** - Decentralized social network
- **Lemmy** - Reddit alternative
- **Warpcast** (Farcaster) - Web3 social
- **Nostr** - Decentralized protocol
- **VK** - Russian social network
- **Telegram** - Channel posting
- **WordPress** - Blog auto-posting
- **ListMonk** - Newsletter integration

## OAuth Configuration for Social Login

If you want to enable "Sign in with GitHub" or other OAuth providers for **user authentication**, you need to create OAuth applications and configure them in Postiz.

**Important:** OAuth credentials for social login are managed directly within Postiz's UI under Settings, NOT in the `.env` file.

### GitHub OAuth (for Sign In with GitHub)

#### 1. Create GitHub OAuth App

1. Go to: https://github.com/settings/developers
2. Click **"New OAuth App"**
3. Fill in the application details:
   - **Application name:** `Postiz` (or your preferred name)
   - **Homepage URL:** `https://postiz.weekendcodeproject.dev`
   - **Authorization callback URL:** `https://postiz.weekendcodeproject.dev/api/auth/oauth/github`
4. Click **"Register application"**
5. You'll receive:
   - **Client ID** (e.g., `Iv1.a1b2c3d4e5f6g7h8`)
   - Click **"Generate a new client secret"** to get the **Client Secret**

#### 2. Configure in Postiz

1. Log into Postiz at https://postiz.weekendcodeproject.dev
2. Go to **Settings** (usually in the top navigation or user menu)
3. Find **OAuth / Integrations** section
4. Add GitHub credentials:
   - **Client ID:** Paste your GitHub OAuth App Client ID
   - **Client Secret:** Paste your GitHub OAuth App Client Secret
5. Save the configuration

#### 3. Test

- Log out of Postiz
- On the login page, you should now see "Sign in with GitHub" button
- Click it to test the OAuth flow

### Google OAuth (for Sign In with Google)

#### 1. Create Google OAuth App

1. Go to: https://console.cloud.google.com/apis/credentials
2. Create a new project or select an existing one
3. Click **"Create Credentials"** → **"OAuth 2.0 Client ID"**
4. Configure the OAuth consent screen if prompted:
   - User Type: External (for public access) or Internal (for organization only)
   - App name: `Postiz`
   - Support email: Your email
5. Create OAuth Client ID:
   - Application type: **Web application**
   - Name: `Postiz`
   - Authorized redirect URIs:
     - `https://postiz.weekendcodeproject.dev/api/auth/oauth/google`
6. Save and copy:
   - **Client ID**
   - **Client Secret**

#### 2. Configure in Postiz

1. Log into Postiz
2. Go to **Settings** → **OAuth / Integrations**
3. Add Google credentials:
   - **Client ID:** Your Google OAuth Client ID
   - **Client Secret:** Your Google OAuth Client Secret
4. Save

### Other OAuth Providers

Follow similar patterns for other authentication providers:

| Provider | Developer Portal | Callback URL |
|----------|-----------------|--------------|
| **Twitter/X** | https://developer.twitter.com/en/portal/dashboard | `https://postiz.weekendcodeproject.dev/api/auth/oauth/twitter` |
| **LinkedIn** | https://www.linkedin.com/developers/apps | `https://postiz.weekendcodeproject.dev/api/auth/oauth/linkedin` |
| **Microsoft** | https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps | `https://postiz.weekendcodeproject.dev/api/auth/oauth/microsoft` |

## Connecting Social Media for Posting

To schedule posts to social media platforms, you need to connect your accounts **within Postiz**:

### General Steps

1. Log into Postiz
2. Navigate to **"Add Channel"** or **"Integrations"**
3. Select the platform you want to connect (e.g., Twitter, LinkedIn)
4. Follow the OAuth flow to authorize Postiz to post on your behalf
5. Each platform will redirect you to their authorization page
6. Grant the requested permissions
7. You'll be redirected back to Postiz with the account connected

### Platform-Specific Notes

#### Twitter/X
- Requires Twitter Developer Account
- API access level determines capabilities (Basic, Pro, Enterprise)
- Create app at: https://developer.twitter.com/en/portal/dashboard

#### Instagram
- Must be a Business or Creator account
- Requires connection through Facebook Business Manager
- Cannot post stories without Facebook Graph API access

#### LinkedIn
- Personal profiles and Company Pages use different OAuth flows
- Company page posting requires admin access to the page

#### Facebook Pages
- Requires Facebook Business account
- Need to grant page management permissions
- Can schedule posts up to 6 months in advance

## Features

### Core Functionality
- **Multi-platform posting:** Schedule posts across multiple social networks simultaneously
- **Content calendar:** Visual calendar view of scheduled posts
- **Media uploads:** Support for images, videos, and GIFs
- **Post preview:** See how posts will appear on each platform
- **Team collaboration:** Multi-user support with roles and permissions
- **Analytics:** Track post performance and engagement

### Post Scheduling
- Schedule posts for specific dates and times
- Optimal time suggestions based on audience activity
- Queue management for automated posting
- Bulk scheduling from CSV imports

### Content Management
- Draft saving and templates
- Hashtag management and suggestions
- @ mention support
- Link shortening and tracking
- Post variations per platform

## Troubleshooting

### "Client ID undefined" Error

**Problem:** OAuth buttons show `client_id=undefined` error

**Solution:** OAuth credentials must be configured in Postiz's Settings UI, not in environment variables. Follow the OAuth configuration steps above.

### 404 Errors on Signup/Login

**Problem:** Getting 404 errors when trying to register or login

**Cause:** Frontend is not correctly configured to call the API through the `/api/` prefix

**Solution:** Already fixed in docker-compose with `NEXT_PUBLIC_BACKEND_URL` including `/api` suffix

### API Connection Issues

**Problem:** Frontend cannot reach backend API

**Check:**
1. Verify Postiz container is healthy: `docker ps | grep postiz`
2. Check logs: `docker logs postiz`
3. Test API: `curl https://postiz.weekendcodeproject.dev/api/auth/can-register`
4. Should return: `{"register":true}`

### Port Conflicts

Postiz exposes port 8095 by default. If this conflicts with another service:

1. Edit `.env`:
   ```bash
   POSTIZ_PORT=8096  # or any available port
   ```
2. Restart: `docker compose --profile productivity up -d postiz`

## Data Backup

### Database Backup

```bash
# Backup Postiz database
docker exec postiz-db pg_dump -U postiz postiz > postiz_backup_$(date +%Y%m%d).sql

# Restore
docker exec -i postiz-db psql -U postiz postiz < postiz_backup_YYYYMMDD.sql
```

### Uploaded Media

Media files are stored in:
```
./files/postiz/uploads/
```

Include this directory in your regular backup routine.

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTIZ_PORT` | `8095` | External port mapping |
| `POSTIZ_DOMAIN` | `postiz-${COMPUTER_NAME}.${BASE_DOMAIN}` | Public domain |
| `POSTIZ_PROTOCOL` | `https` | HTTP or HTTPS |
| `POSTIZ_MEMORY_LIMIT` | `2g` | Container memory limit |
| `POSTIZ_DBNAME` | `postiz` | PostgreSQL database name |
| `POSTIZ_DBUSER` | `postiz` | PostgreSQL user |
| `POSTIZ_DBPASS` | `postiz_password_2024` | PostgreSQL password |
| `POSTIZ_NEXTAUTH_SECRET` | (random) | NextAuth session secret |
| `POSTIZ_JWT_SECRET` | (random) | JWT token secret |

## Updating Postiz

```bash
# Pull latest image
docker compose pull postiz

# Recreate container
docker compose --profile productivity up -d postiz

# Check logs
docker logs -f postiz
```

## Removing Postiz

```bash
# Stop and remove containers
docker compose --profile productivity down postiz postiz-db postiz-redis

# Remove volumes (CAUTION: Deletes all data)
docker volume rm wcp-coder_postiz-db-data wcp-coder_postiz-redis-data

# Remove uploaded files
rm -rf ./files/postiz/
```

## Additional Resources

- **Postiz GitHub:** https://github.com/gitroomhq/postiz-app
- **Documentation:** https://postiz.com/docs
- **Community:** https://discord.gg/postiz (check GitHub for invite link)

## Security Considerations

1. **Change default secrets** in `.env`:
   - `POSTIZ_NEXTAUTH_SECRET`
   - `POSTIZ_JWT_SECRET`
   - `POSTIZ_DBPASS`

2. **OAuth credentials** are stored in Postiz's database, not in `.env`

3. **Use strong passwords** for user accounts

4. **Regular backups** of database and uploaded media

5. **Keep Postiz updated** to get security patches

6. **Limit network exposure** - Only expose via Traefik/HTTPS, not direct port access

## Common Use Cases

### Personal Brand Management
- Schedule consistent content across platforms
- Maintain presence during vacations
- Cross-post to multiple networks

### Team Collaboration
- Multiple team members can schedule posts
- Approval workflows for content
- Centralized content calendar

### Content Repurposing
- Post blog articles to social media
- Share video content across platforms
- Adapt content for each platform's format

### Analytics & Optimization
- Track which content performs best
- Identify optimal posting times
- Measure engagement across platforms
