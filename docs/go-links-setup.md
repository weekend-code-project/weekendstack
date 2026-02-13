# Smart Links (/go) Setup

This stack includes a tiny redirect service that enables “smart links” from Glance.

## What it does

When you click a link like `/go/coder` from Glance, the redirector sends you to the correct hostname based on how you accessed Glance:

- From `http://glance.lab/go/coder` → `http://coder.lab/`
- From `https://glance.${BASE_DOMAIN}/go/coder` → `https://coder.${BASE_DOMAIN}/`

This keeps Glance bookmarks consistent across local `.lab` and public `${BASE_DOMAIN}` access.

## Files

- Redirector code: `config/link-router/server.py`
- Compose service: `compose/docker-compose.core.yml` (`link-router`)

## Start

```bash
docker compose --profile core up -d --build link-router
```

## Test (no DNS required)

```bash
# HTTP (local)
curl -sS -D- -o /dev/null -H 'Host: glance.lab' http://127.0.0.1/go/coder | head

# HTTPS (tunnel)
curl -k -sS -D- -o /dev/null -H 'Host: glance.${BASE_DOMAIN}' https://127.0.0.1/go/coder | head
```

## Notes

- Traefik is configured with **two routers** so `/go/*` works on both entrypoints:
  - `web` (HTTP) for `.lab`
  - `websecure` (HTTPS) for `${BASE_DOMAIN}`
