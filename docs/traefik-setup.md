# Traefik Reverse Proxy Setup

## Overview

Traefik acts as a reverse proxy and load balancer, routing traffic to services and Coder workspaces with automatic SSL and authentication.

## Directory Structure

```
config/traefik/
├── config.yml              # Static Traefik configuration
└── auth/                   # Dynamic authentication files
    ├── dynamic-*.yaml      # Per-workspace routing rules
    └── hashed_password-*   # Per-workspace password hashes
```

## Configuration

### Environment Variables

Set in `.env` file:

```bash
# Traefik configuration
TRAEFIK_VERSION=v2.10
TRAEFIK_AUTH_DIR=${CONFIG_BASE_DIR}/traefik/auth

# Domain configuration
DOMAIN=localhost
```

### Docker Compose Service

From `docker-compose.traefik.yml`:

```yaml
traefik:
  image: traefik:${TRAEFIK_VERSION}
  container_name: traefik
  command:
    - "--api.insecure=true"
    - "--providers.docker=true"
    - "--providers.docker.exposedbydefault=false"
    - "--providers.file.directory=/etc/traefik/dynamic"
    - "--providers.file.watch=true"
    - "--entrypoints.web.address=:80"
  ports:
    - "80:80"
    - "8080:8080"  # Traefik dashboard
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ${TRAEFIK_CONFIG_DIR}/config.yml:/etc/traefik/traefik.yml:ro
    - ${TRAEFIK_AUTH_DIR}:/etc/traefik/dynamic:ro
  networks:
    - web
```

## Initial Setup

### 1. Directory Creation

The `coder-init` service automatically creates the auth directory:

```yaml
coder-init:
  image: alpine:latest
  command: >
    sh -c "
    chmod 777 /traefik-auth &&
    echo 'Traefik auth directory: /traefik-auth (777)'
    "
  volumes:
    - ${TRAEFIK_AUTH_DIR}:/traefik-auth
```

**Why 777 permissions?**
- Coder workspace containers (running as privileged) need to write auth files
- Container startup runs `sudo chown -R coder:coder /traefik-auth`
- Files written: `hashed_password-<workspace>` and `dynamic-<workspace>.yaml`

### 2. Static Configuration

Create `config/traefik/config.yml`:

```yaml
# Enable API and dashboard
api:
  dashboard: true
  insecure: true

# Docker provider
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: web
  
  # File provider for dynamic configs
  file:
    directory: /etc/traefik/dynamic
    watch: true

# Entry points
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

# Logging
log:
  level: INFO
```

### 3. Start Traefik

```bash
docker-compose up -d traefik
```

### 4. Access Dashboard

Open browser to http://localhost:8080

## Dynamic Configuration

### Automatic Workspace Routing

Coder workspaces automatically create Traefik configuration:

#### For Private Workspaces (`make_public=false`)

Creates two files in `${TRAEFIK_AUTH_DIR}`:

**1. Password Hash** (`hashed_password-<workspace-name>`):
```
user:$2y$05$... (bcrypt hash)
```

**2. Dynamic Config** (`dynamic-<workspace-name>.yaml`):
```yaml
http:
  routers:
    workspace-name:
      rule: "Host(`workspace-name.localhost`)"
      service: workspace-name
      middlewares:
        - workspace-name-auth
  
  services:
    workspace-name:
      loadBalancer:
        servers:
          - url: "http://workspace-container:PORT"
  
  middlewares:
    workspace-name-auth:
      basicAuth:
        usersFile: /etc/traefik/dynamic/hashed_password-workspace-name
```

#### For Public Workspaces (`make_public=true`)

No auth files created. Container gets Traefik labels directly:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.workspace-name.rule=Host(`workspace-name.localhost`)"
  - "traefik.http.services.workspace-name.loadbalancer.server.port=PORT"
```

### Manual Service Configuration

For non-Coder services, use Docker labels:

```yaml
services:
  my-service:
    image: nginx:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myservice.rule=Host(`myservice.localhost`)"
      - "traefik.http.routers.myservice.entrypoints=web"
      - "traefik.http.services.myservice.loadbalancer.server.port=80"
    networks:
      - web
```

With authentication:

```yaml
services:
  my-service:
    image: nginx:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myservice.rule=Host(`myservice.localhost`)"
      - "traefik.http.routers.myservice.middlewares=myservice-auth"
      - "traefik.http.middlewares.myservice-auth.basicauth.users=user:$$apr1$$..."
    networks:
      - web
```

## Authentication

### Generate Password Hash

Using htpasswd:

```bash
# Install htpasswd
sudo apt-get install apache2-utils

# Generate password hash (bcrypt)
htpasswd -nbB username password
```

Output:
```
username:$2y$05$...hash...
```

### Create Manual Auth Files

**1. Create password file:**
```bash
echo 'user:$2y$05$...hash...' > config/traefik/auth/hashed_password-myservice
```

**2. Create dynamic config:**
```yaml
# config/traefik/auth/dynamic-myservice.yaml
http:
  routers:
    myservice:
      rule: "Host(`myservice.localhost`)"
      service: myservice
      middlewares:
        - myservice-auth
  
  services:
    myservice:
      loadBalancer:
        servers:
          - url: "http://myservice:80"
  
  middlewares:
    myservice-auth:
      basicAuth:
        usersFile: /etc/traefik/dynamic/hashed_password-myservice
```

Traefik automatically reloads the configuration (file watcher enabled).

## Workspace Integration

### How Coder Workspaces Set Up Routing

From template startup script:

```bash
# 1. Generate workspace secret
WORKSPACE_SECRET="random-generated-value"

# 2. Create password hash
echo "user:$(htpasswd -nbB user "$WORKSPACE_SECRET" | cut -d: -f2)" \
  > /traefik-auth/hashed_password-${WORKSPACE_NAME}

# 3. Create dynamic config
cat > /traefik-auth/dynamic-${WORKSPACE_NAME}.yaml <<EOF
http:
  routers:
    ${WORKSPACE_NAME}:
      rule: "Host(\`${WORKSPACE_NAME}.localhost\`)"
      service: ${WORKSPACE_NAME}
      middlewares:
        - ${WORKSPACE_NAME}-auth
  
  services:
    ${WORKSPACE_NAME}:
      loadBalancer:
        servers:
          - url: "http://workspace_container:${PORT}"
  
  middlewares:
    ${WORKSPACE_NAME}-auth:
      basicAuth:
        usersFile: /etc/traefik/dynamic/hashed_password-${WORKSPACE_NAME}
EOF
```

### Workspace Cleanup

When workspace is deleted, Coder template removes auth files:

```bash
rm -f /traefik-auth/hashed_password-${WORKSPACE_NAME}
rm -f /traefik-auth/dynamic-${WORKSPACE_NAME}.yaml
```

## Domain Configuration

### Using Custom Domain

1. **Update .env:**
   ```bash
   DOMAIN=example.com
   ```

2. **DNS Configuration:**
   - Point `*.example.com` to your server IP
   - Use wildcard DNS or individual A records

3. **Update workspace routing rule:**
   ```yaml
   rule: "Host(`workspace-name.example.com`)"
   ```

### SSL/TLS with Let's Encrypt

1. **Enable HTTPS entrypoint:**
   ```yaml
   entryPoints:
     web:
       address: ":80"
       http:
         redirections:
           entryPoint:
             to: websecure
             scheme: https
     
     websecure:
       address: ":443"
       http:
         tls:
           certResolver: letsencrypt
   ```

2. **Configure Let's Encrypt:**
   ```yaml
   certificatesResolvers:
     letsencrypt:
       acme:
         email: your-email@example.com
         storage: /letsencrypt/acme.json
         httpChallenge:
           entryPoint: web
   ```

3. **Mount storage for certificates:**
   ```yaml
   volumes:
     - ./letsencrypt:/letsencrypt
   ```

## Troubleshooting

### Error: 404 Page Not Found

**Cause**: Route not configured or service not reachable

**Debug**:
1. Check Traefik dashboard: http://localhost:8080
2. Verify service is running: `docker ps`
3. Check dynamic configs: `ls -la config/traefik/auth/`
4. View Traefik logs: `docker logs traefik`

**Common fixes**:
- Ensure service has `traefik.enable=true` label
- Verify host rule matches request URL
- Check service is on `web` network
- Confirm dynamic config file syntax

### Error: Permission Denied (Workspace Auth Files)

**Cause**: Traefik auth directory has wrong permissions

**Fix**:
```bash
chmod 777 ./config/traefik/auth
docker-compose restart
```

**Verify**:
```bash
ls -ld ./config/traefik/auth/
# Should show: drwxrwxrwx (777)
```

### Error: 401 Unauthorized (Wrong Password)

**Cause**: Password hash mismatch or file not found

**Debug**:
1. Check password file exists: `ls config/traefik/auth/hashed_password-*`
2. Verify hash format (should start with `$2y$` for bcrypt)
3. Check dynamic config references correct file

**Fix**: Regenerate password hash:
```bash
htpasswd -nbB user password > config/traefik/auth/hashed_password-service
```

### Error: Service Unreachable

**Cause**: Service not on correct network or wrong port

**Debug**:
1. Check networks: `docker network inspect web`
2. Verify service port: `docker port <container>`
3. Test direct access: `curl http://container:port`

**Fix**:
- Add service to `web` network
- Correct loadbalancer port in config
- Ensure container exposes correct port

### Dynamic Config Not Loading

**Cause**: File watcher not enabled or syntax error

**Debug**:
1. Check Traefik logs: `docker logs traefik | grep -i error`
2. Verify file provider enabled in config
3. Test YAML syntax: `yamllint dynamic-*.yaml`

**Fix**:
```yaml
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true  # Enable file watching
```

## Best Practices

### Security

1. ✅ Use HTTPS in production (Let's Encrypt)
2. ✅ Enable authentication for sensitive services
3. ✅ Use strong passwords (htpasswd -nbB)
4. ✅ Limit Traefik dashboard access
5. ❌ Don't expose API insecurely in production

### Performance

1. ✅ Use `exposedByDefault: false` (explicit opt-in)
2. ✅ Enable access logs only when debugging
3. ✅ Use connection limits for public services
4. ✅ Enable compression middleware
5. ✅ Configure rate limiting

### Maintenance

1. ✅ Regular backups of dynamic configs
2. ✅ Monitor Traefik logs
3. ✅ Update Traefik version regularly
4. ✅ Clean up unused auth files
5. ✅ Document custom configurations

## Advanced Configuration

### Rate Limiting

```yaml
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
```

Apply to router:
```yaml
routers:
  myservice:
    middlewares:
      - rate-limit
```

### IP Whitelist

```yaml
http:
  middlewares:
    ip-whitelist:
      ipWhiteList:
        sourceRange:
          - "192.168.1.0/24"
          - "10.0.0.0/8"
```

### Headers

```yaml
http:
  middlewares:
    security-headers:
      headers:
        sslRedirect: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
```

### Compression

```yaml
http:
  middlewares:
    compression:
      compress: {}
```

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [coder-setup.md](coder-setup.md) - Coder workspace integration
- [network-architecture.md](network-architecture.md) - Network overview
- [deployment-guide.md](deployment-guide.md) - Production deployment
