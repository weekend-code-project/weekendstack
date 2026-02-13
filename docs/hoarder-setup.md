# Hoarder (Karakeep) Setup

Hoarder (Karakeep) is a “bookmark everything” service.

## Access

- Local (LAN): `http://hoarder.lab`
- Optional public (tunnel): `https://hoarder.${BASE_DOMAIN}`

## Files

- Compose services: `compose/docker-compose.productivity.yml`
  - `hoarder`
  - `hoarder-chrome`
  - `hoarder-meilisearch`

## Required secrets

Set these in `.env` before first real use:

- `HOARDER_NEXTAUTH_SECRET`
- `HOARDER_MEILI_MASTER_KEY`

## Start

```bash
docker compose --profile productivity up -d hoarder hoarder-chrome hoarder-meilisearch
```

## Validate

- Create a bookmark.
- Restart the containers.
- Confirm the bookmark is still present (data persistence).
