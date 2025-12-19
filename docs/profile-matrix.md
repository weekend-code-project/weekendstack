# Profile-Service Matrix

This matrix shows which Docker Compose profiles start each service in the Weekend Stack. Combine the columns to quickly decide which `docker compose --profile ...` flags you need without digging through every compose file.

> NOTE: Table auto-generated via `tools/generate_profile_matrix.py`. Edit compose files or this script rather than the table directly.

## Legend
- `default`: service has **no explicit profile** and is always part of the base selection (runs on `docker compose up` and whenever any profile is requested).
- Other columns match the profile names used across the compose files.
- `✓` means the service declares that profile.

<!-- PROFILE-MATRIX:START -->
| Category | Service | default | all | gpu | ai | core | dev | development | dev-tools | gitlab | proxy | networking | automation | media | monitoring | personal | productivity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AI & ML | anythingllm |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | comfyui |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | diffrhythm |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | librechat |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | librechat-db |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | localai |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | open-webui |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | privategpt |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | searxng |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | stable-diffusion-webui |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | whisper |  | ✓ |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |
| AI & ML | whisperx |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |
| Core | homer |  | ✓ |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |
| Core | homer-public |  | ✓ |  |  |  |  |  |  |  |  | ✓ |  |  |  |  |  |
| Core | vaultwarden |  | ✓ |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |
| Development | coder |  | ✓ |  |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |
| Development | coder-init |  | ✓ |  |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |
| Development | database |  | ✓ |  |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |
| Development | gitea |  | ✓ |  |  |  |  | ✓ |  |  |  |  |  |  |  |  |  |
| Development | gitea-db |  | ✓ |  |  |  |  | ✓ |  |  |  |  |  |  |  |  |  |
| Development | gitlab |  | ✓ |  |  |  | ✓ |  |  | ✓ |  |  |  |  |  |  |  |
| Development | registry-cache |  | ✓ |  |  |  |  |  | ✓ |  |  |  |  |  |  |  |  |
| Development | socat |  | ✓ |  |  |  | ✓ |  |  |  |  |  |  |  |  |  |  |
| Productivity | activepieces |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | activepieces-db |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | activepieces-redis |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | bytestash |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | docmost |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | docmost-db |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | docmost-redis |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | excalidraw |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | focalboard |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | it-tools |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | n8n |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | n8n-db |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | nocodb |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | nocodb-db | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| Productivity | paperless-db | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| Productivity | paperless-ngx |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | paperless-redis | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| Productivity | postiz |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | postiz-db |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | postiz-redis |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | trilium |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Productivity | vikunja |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |
| Networking | cloudflare-tunnel |  | ✓ |  |  |  |  |  |  |  | ✓ | ✓ |  |  |  |  |  |
| Networking | pihole |  | ✓ |  |  |  |  |  |  |  |  | ✓ |  |  |  |  |  |
| Networking | traefik |  | ✓ |  |  |  |  |  |  |  | ✓ | ✓ |  |  |  |  |  |
| Automation | homeassistant |  | ✓ |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |  |
| Automation | nodered |  | ✓ |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |  |
| Media | immich-db |  | ✓ |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |
| Media | immich-machine-learning |  | ✓ |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |
| Media | immich-redis |  | ✓ |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |
| Media | immich-server |  | ✓ |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |
| Media | kavita |  | ✓ |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |
| Media | navidrome |  | ✓ |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |  |
| Monitoring | dozzle |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | duplicati |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | netbox |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | netbox-postgres |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | netbox-redis |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | netdata |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | portainer |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | uptime-kuma |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Monitoring | wud |  | ✓ |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| Personal | firefly |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |
| Personal | mealie |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |
| Personal | wger |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |
| Personal | wger-nginx |  | ✓ |  |  |  |  |  |  |  |  |  |  |  |  | ✓ |  |
<!-- PROFILE-MATRIX:END -->

## Usage Patterns
- **Start everything (default + GPU)**: `docker compose up -d` uses the `x-default-profile` (`all` + `gpu`).
- **Skip GPU workloads**: `docker compose --profile all up -d` omits every `gpu`-only row.
- **Targeted groups**: chain profiles, e.g. `docker compose --profile dev --profile networking up -d` (Coder + Traefik) or `docker compose --profile productivity --profile personal up -d` (office + lifestyle).
- **Single-service helpers**: use custom names like `--profile gitlab` when you only need heavy services temporarily.
- **Always-on dependencies** (`default` column) follow their parent apps; consider adding profile tags later if you want those DB/Redis containers to stay dormant until requested.
