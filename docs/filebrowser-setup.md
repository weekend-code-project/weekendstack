# File Browser Setup

File Browser provides a simple web UI to browse and manage files in this repo’s `files/` directory.

## Access

- Local (LAN): `http://filebrowser.lab`
- Optional public (tunnel): `https://filebrowser.${BASE_DOMAIN}` (only if you intentionally expose it)

## Scope (important)

This stack mounts only:

- `./files` → `/srv`

It does **not** mount host root paths.

## Files

- Compose service: `docker-compose.productivity.yml` (`filebrowser`)

## Start

```bash
docker compose --profile productivity up -d filebrowser
```

## Validate

- Upload/download a test file and confirm it appears under the repo `files/` directory.
