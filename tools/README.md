# Stack Health Testing Tools

This directory contains scripts to help diagnose and test the Weekend Stack health and routing.

## Available Scripts

### 1. `test_stack_health.sh`

Comprehensive health check that tests:
- Traefik container status and API accessibility
- Critical container health
- HTTP→HTTPS redirect middleware loading
- HTTP→HTTPS redirects for key services
- HTTPS access for services
- Container error states

**Usage:**
```bash
./tools/test_stack_health.sh
```

**Example Output:**
```
========================================
  Weekend Stack Health Check
========================================

[1/6] Checking Core Services...
  ✓ Traefik Container
  ✓ Traefik API (78 routers discovered)

[2/6] Checking Critical Containers...
  ✓ traefik
  ✓ glance
  ✓ coder
  ...

[4/6] Testing HTTP→HTTPS Redirects...
  ✓ coder.lab → https://coder.lab/
  ✓ home.lab → https://home.lab/
  ...
```

### 2. `list_stopped_containers.sh`

Lists all containers that are not running (Created, Exited, Dead states).

**Usage:**
```bash
./tools/list_stopped_containers.sh
```

## Common Scenarios

### Containers Not Starting

If containers are in "Created" state but not running:

```bash
# Check which containers are stopped
./tools/list_stopped_containers.sh

# Start specific services
docker compose up -d <service-name>

# Check logs for errors
docker logs <container-name>
```

### HTTP→HTTPS Redirects Not Working

If a service is not redirecting HTTP to HTTPS:

1. Run health check to identify which services have issues:
   ```bash
   ./tools/test_stack_health.sh
   ```

2. Check if the redirect middleware is loaded:
   ```bash
   curl -s http://localhost:8081/api/http/middlewares/redirect-to-https@file | jq
   ```

3. Check the service's Traefik router configuration:
   ```bash
   curl -s http://localhost:8081/api/http/routers | jq '.[] | select(.name | contains("<service-name>"))'
   ```

4. If the router is missing, the container labels might not have been loaded. Recreate the container:
   ```bash
   docker compose up -d <service-name>
   ```

### Service Not Accessible

If a service shows as running but isn't accessible:

1. Check if Traefik has discovered the routers:
   ```bash
   curl -s http://localhost:8081/api/http/routers | jq '.[] | select(.name | contains("<service-name>")) | {name, rule, entryPoints}'
   ```

2. Verify the container is on the correct network:
   ```bash
   docker inspect <container-name> | jq '.[0].NetworkSettings.Networks | keys'
   ```
   
   Should include `shared-network`.

3. Check container logs:
   ```bash
   docker logs <container-name>
   ```

## Quick Reference

### View Traefik Dashboard
```bash
# Open in browser:
http://localhost:8081/dashboard/
```

### List All Traefik Routers
```bash
curl -s http://localhost:8081/api/http/routers | jq 'keys'
```

### Test a Specific Domain
```bash
# Test HTTP redirect
curl -v -H "Host: <service>.lab" http://127.0.0.1/

# Test HTTPS access
curl -vk --resolve "<service>.lab:443:127.0.0.1" https://<service>.lab/
```

### Restart Entire Stack
```bash
docker compose down && docker compose up -d
```

### Restart Traefik (to reload configuration)
```bash
docker compose restart traefik
```

## Troubleshooting Tips

1. **Container in "Created" state**: Run `docker compose up -d <service>` to start it
2. **Traefik not discovering routers**: Recreate the container with `docker compose up -d <service>`
3. **Networks not found after VM restart**: Run `docker compose down --remove-orphans && docker compose up -d`
4. **Middleware not loading**: Check that `/opt/stacks/weekendstack/data/traefik-auth/` contains the middleware YAML files
5. **Certificate errors**: Check `/opt/stacks/weekendstack/config/traefik/certs/` has valid certificates

## Environment Variables

The health check script loads environment variables from `.env`:
- `LAB_DOMAIN` - Local domain suffix (default: `lab`)
- `BASE_DOMAIN` - External domain (default: `weekendcodeproject.dev`)
- `HOST_IP` - Host machine IP address
- `TRAEFIK_DOCKER_NETWORK` - Network Traefik watches (default: `shared-network`)
