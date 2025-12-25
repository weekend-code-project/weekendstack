# Glance Setup

Glance is a YAML-configured dashboard used as the primary start page.

## Access

- Local (LAN): `http://glance.lab`
- Optional public (tunnel): `https://glance.${BASE_DOMAIN}`

## Files

- Dashboard config: `config/glance/glance.yml`
- Compose service: `docker-compose.core.yml` (`glance`)

## Start

```bash
docker compose --profile core up -d glance
```

## Notes

- Glance is configured with `server.proxied: true` for Traefik.
- Most bookmarks use `/go/<service>` so the same dashboard works from both `.lab` (HTTP) and `${BASE_DOMAIN}` (HTTPS).
- If `glance.lab` redirects to `home.lab`, it usually means the `glance` container is not running (no matching router).
