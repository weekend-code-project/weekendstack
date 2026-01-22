# Local Authentication Pattern

## Overview

This document describes the authentication strategy for services accessed via `.lab` domain (local network) versus external domain (Cloudflare tunnel).

## Security Model

### Trusted Network Assumption
- **`.lab` domain** routes are considered local/trusted network access
- Direct IP access (`http://192.168.x.x:port`) has same trust level as `.lab`
- No practical way to enforce auth on direct IP access
- Therefore, `.lab` routes do not require authentication middleware

### Internet-Facing Security
- **External domain** routes (`*.weekendcodeproject.dev`) go through Cloudflare tunnel
- These routes **require** Traefik authentication middleware
- Auth middleware protects against unauthorized internet access

## Implementation Pattern

### Standard 3-Router Configuration

For each service, implement three routers:

#### 1. HTTP Redirect Router (`.lab` domain)
```yaml
# Local .lab domain (HTTP) - Redirect to HTTPS
- traefik.http.routers.service-lab-http.entrypoints=web
- traefik.http.routers.service-lab-http.rule=Host(`service.${LAB_DOMAIN}`)
- traefik.http.routers.service-lab-http.middlewares=redirect-to-https@file
- traefik.http.routers.service-lab-http.service=service
```

#### 2. HTTPS Local Router (`.lab` domain) - **NO AUTH**
```yaml
# Local .lab domain (HTTPS) - No auth for local network
- traefik.http.routers.service-lab.entrypoints=websecure
- traefik.http.routers.service-lab.rule=Host(`service.${LAB_DOMAIN}`)
- traefik.http.routers.service-lab.tls=true
- traefik.http.routers.service-lab.service=service
```
**Note:** No `middlewares` line with auth - local network is trusted

#### 3. HTTPS External Router (external domain) - **WITH AUTH**
```yaml
# External domain (HTTPS via Cloudflare) - Auth required
- traefik.http.routers.service-external.entrypoints=websecure
- traefik.http.routers.service-external.rule=Host(`service.${BASE_DOMAIN}`)
- traefik.http.routers.service-external.tls=true
- traefik.http.routers.service-external.middlewares=service-auth@file
- traefik.http.routers.service-external.service=service
```
**Note:** `middlewares=service-auth@file` protects external access

## Current Implementation

### Services with Auth Protection

All services below have auth **only** on external routes, not on `.lab` routes:

| Service | Auth Middleware | External Auth | .lab Auth |
|---------|----------------|---------------|-----------|
| searxng | `searxng-auth@file` | ✅ Yes | ❌ No |
| localai | `ai-services-auth@file` | ✅ Yes | ❌ No |
| anythingllm | `ai-services-auth@file` | ✅ Yes | ❌ No |
| whisper | `ai-services-auth@file` | ✅ Yes | ❌ No |
| it-tools | `it-tools-auth@file` | ✅ Yes | ❌ No |
| excalidraw | `it-tools-auth@file` | N/A (no external) | ❌ No |

### Auth Middleware Files

Authentication middleware is defined in `/opt/stacks/weekendstack/data/traefik-auth/`:
- `searxng-auth.yaml` - SearXNG specific auth
- `ai-services-auth.yaml` - AI services auth (LocalAI, AnythingLLM, Whisper)
- `it-tools-auth.yaml` - IT Tools auth (it-tools, excalidraw)

These files remain in place and are applied only to external routes.

## When to Add New Services

### Service Needs Public Internet Access
If a service should be accessible via Cloudflare tunnel:
1. Add external router with auth middleware
2. Add `.lab` routers **without** auth middleware
3. Create or reuse appropriate auth middleware file

### Service is Local-Only
If a service should only be accessible on local network:
1. Only create `.lab` routers (HTTP + HTTPS)
2. No external router needed
3. No auth middleware required

## Optional: Toggle Local Auth

While not currently implemented, local auth could be toggled using environment variables:

```yaml
# Example optional local auth pattern
- traefik.http.routers.service-lab.middlewares=${ENABLE_LOCAL_AUTH:-}service-auth@file

# In .env file
ENABLE_LOCAL_AUTH=         # Empty = no local auth (default)
ENABLE_LOCAL_AUTH=,        # Comma prefix = enable local auth
```

**Note:** This is not implemented because:
1. Direct IP access bypasses Traefik auth anyway
2. Network segmentation is the proper security control
3. Adds complexity without meaningful security benefit

## Security Recommendations

### Network Segmentation
- Run services on isolated network (VLAN, subnet)
- Use firewall rules to restrict access to trusted devices
- Consider VPN for remote access to `.lab` domain

### Access Control Priority
1. **Network-level** - Firewall, VLANs, VPN (most effective)
2. **Application-level** - Service built-in auth (if available)
3. **Reverse proxy auth** - Traefik middleware (external only)

### What This Pattern Does NOT Protect Against
- Malicious devices on local network
- Compromised local devices
- Physical access to network
- Direct IP:port access

### What This Pattern DOES Protect Against
- Unauthorized internet access via Cloudflare tunnel
- Exposure of services without authentication to public internet
- Credential harvesting from external attackers

## Related Documentation
- [Traefik Setup](traefik-setup.md)
- [Local HTTPS Setup](local-https-setup.md)
- [Network Architecture](network-architecture.md)
