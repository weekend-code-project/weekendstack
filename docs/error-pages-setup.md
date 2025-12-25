# Error Pages Setup

## Overview

Custom error pages are provided by the `error-pages` service using the `tarampampam/error-pages` Docker image. This service renders beautiful error pages for HTTP errors (4xx, 5xx) instead of the default Traefik error pages.

## Configuration

The error pages theme is configured via environment variables in `.env`:

```bash
ERROR_PAGES_THEME=ghost           # Theme to use (see available themes below)
ERROR_PAGES_SHOW_DETAILS=false    # Whether to show error details
ERROR_PAGES_MEMORY_LIMIT=64m      # Memory limit for the service
```

## Available Themes

- **ghost** (default) - Clean, minimal design
- **l7-light** - Light mode Layer 7 theme
- **l7-dark** - Dark mode Layer 7 theme
- **shuffle** - Randomized colorful design
- **noise** - Static/noise effect
- **hacker-terminal** - Terminal/Matrix style
- **cats** - Fun cat-themed errors
- **lost-in-space** - Space-themed design
- **app-down** - Application downtime page
- **connection** - Connection error themed
- **orient** - Oriental/zen design

Full list and previews: https://github.com/tarampampam/error-pages

## Usage

### Applying to Individual Services

To use custom error pages on a specific service, add the `error-pages@file` middleware to your router labels:

```yaml
services:
  myservice:
    # ... other configuration ...
    labels:
      - traefik.enable=true
      - traefik.http.routers.myservice.rule=Host(`myservice.lab`)
      - traefik.http.routers.myservice.entrypoints=web
      - traefik.http.routers.myservice.middlewares=error-pages@file
      - traefik.http.services.myservice.loadbalancer.server.port=8080
```

### Combining with Other Middlewares

If you need to use multiple middlewares, chain them with commas:

```yaml
- traefik.http.routers.myservice.middlewares=basic-auth@file,error-pages@file
```

## How It Works

1. The `error-pages` service runs a lightweight web server that generates error pages
2. The Traefik middleware `error-pages@file` is defined in `/config/traefik/auth/dynamic-error-pages.yaml`
3. When a router with this middleware encounters an HTTP error (400-599) **from the backend service**, Traefik redirects to the error-pages service
4. The error-pages service renders a custom page based on the error status code and configured theme

**Important**: This middleware only handles errors returned by backend services. When Traefik itself cannot find a matching router (no route configured), it returns its default 404 page. This is expected behavior:
- `https://cockpit.weekendcodeproject.dev/` → Traefik 404 (no external router, local-only service)
- `https://service-not-running.weekendcodeproject.dev/` → Traefik 404 (container not running, no router registered)
- `http://glance.lab/bad-page` → Custom 404 (if error-pages middleware is applied to glance router)

For local `.lab` domains, the catchall redirect provides a better UX by redirecting unknown services to the dashboard.

## Testing

Test the error pages by accessing a non-existent service:

```bash
# Through Docker network (direct)
docker run --rm --network shared-network curlimages/curl:latest \\
  curl -sS http://error-pages:8080/404.html

# Through Traefik (requires middleware applied to a router)
curl http://myservice.lab/nonexistent-page
```

## Customization

To change the theme:

1. Edit `.env` and set `ERROR_PAGES_THEME` to your desired theme
2. Recreate the error-pages container:
   ```bash
   docker compose up -d --force-recreate error-pages
   ```

No Traefik restart is required when changing themes, only when adding/removing the middleware from routers.
