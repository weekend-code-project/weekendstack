# New Services Implementation Plan

**Created:** December 4, 2025  
**Status:** Planning Phase

## Overview

This document tracks the implementation of new services into the weekendstack Docker environment. Each service follows the established patterns:

- Grouped into themed compose files (`docker-compose.<group>.yml`)
- All settings configurable via `.env` file
- Consistent labeling for Traefik integration
- Profile-based activation (`--profile <name>`)
- Dedicated networks per service group
- Health checks where applicable
- Resource limits configurable via `.env`

---

## Services to Implement

| Service | Target File | Profile | Priority |
|---------|-------------|---------|----------|
| Immich | `docker-compose.media.yml` (NEW) | media | High |
| Kavita | `docker-compose.media.yml` (NEW) | media | Medium |
| Navidrome | `docker-compose.media.yml` (NEW) | media | Medium |
| Bitwarden/Vaultwarden | `docker-compose.core.yml` | core | High |
| Home Assistant | `docker-compose.automation.yml` (NEW) | automation | High |
| Pi-Hole | `docker-compose.networking.yml` (RENAME from traefik) | networking | High |
| GitLab | `docker-compose.dev.yml` | dev | Medium |
| Focalboard | `docker-compose.productivity.yml` | productivity | Low |

---

## Phase 1: File Structure Changes

### [ ] 1.1 Rename `docker-compose.traefik.yml` → `docker-compose.networking.yml`
- Update all references in `docker-compose.yml` include section
- Add networking-network alongside traefik-network
- Update comments/documentation

### [ ] 1.2 Create `docker-compose.media.yml`
- New file for media services (Immich, Kavita, Navidrome)
- Create media-network
- Add to `docker-compose.yml` include section

### [ ] 1.3 Create `docker-compose.automation.yml`
- New file for home automation services (Home Assistant)
- Create automation-network
- Add to `docker-compose.yml` include section

### [ ] 1.4 Update `docker-compose.yml`
- Add new includes for media and automation
- Update traefik reference to networking
- Update available profiles comment block

---

## Phase 2: Media Services (`docker-compose.media.yml`)

### [ ] 2.1 Immich - Photo/Video Management
**Image:** `ghcr.io/immich-app/immich-server:release`  
**Components:** Server, Machine Learning, Redis, PostgreSQL  
**Profile:** `media`

#### Services Required:
- `immich-server` - Main application
- `immich-machine-learning` - ML processing for face/object detection
- `immich-redis` - Cache layer
- `immich-db` - PostgreSQL database

#### .env Variables to Add:
```env
# =============================================================================
# MEDIA SERVICES CONFIGURATION (OPTIONAL - Profile: media)
# =============================================================================

# Immich - Photo/Video Management
MEDIA_IMMICH_PROFILE=media
IMMICH_PORT=2283
IMMICH_MEMORY_LIMIT=4g
IMMICH_ML_MEMORY_LIMIT=4g
IMMICH_TRAEFIK_ENABLE=true
IMMICH_DOMAIN=photos.${BASE_DOMAIN}
IMMICH_PROTOCOL=https
IMMICH_DB_PASSWORD=immich_db_password_2024
IMMICH_UPLOAD_LOCATION=${FILES_BASE_DIR}/immich/upload
IMMICH_EXTERNAL_PATH=${FILES_BASE_DIR}/immich/external
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/immich/upload` → `/usr/src/app/upload`
- `${FILES_BASE_DIR}/immich/external` → `/usr/src/app/external` (optional external library)

---

### [ ] 2.2 Kavita - Digital Library (Comics/Books/Manga)
**Image:** `jvmilazz0/kavita:latest`  
**Profile:** `media`

#### .env Variables to Add:
```env
# Kavita - Digital Library (Comics, Manga, Books)
MEDIA_KAVITA_PROFILE=media
KAVITA_PORT=5000
KAVITA_MEMORY_LIMIT=2g
KAVITA_TRAEFIK_ENABLE=true
KAVITA_DOMAIN=library.${BASE_DOMAIN}
KAVITA_PROTOCOL=https
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/kavita/config` → `/kavita/config`
- `${FILES_BASE_DIR}/kavita/data` → `/data` (library location)

---

### [ ] 2.3 Navidrome - Music Server
**Image:** `deluan/navidrome:latest`  
**Profile:** `media`

#### .env Variables to Add:
```env
# Navidrome - Music Streaming Server
MEDIA_NAVIDROME_PROFILE=media
NAVIDROME_PORT=4533
NAVIDROME_MEMORY_LIMIT=1g
NAVIDROME_TRAEFIK_ENABLE=true
NAVIDROME_DOMAIN=music.${BASE_DOMAIN}
NAVIDROME_PROTOCOL=https
NAVIDROME_MUSIC_FOLDER=${FILES_BASE_DIR}/navidrome/music
NAVIDROME_DATA_FOLDER=${FILES_BASE_DIR}/navidrome/data
NAVIDROME_SCAN_SCHEDULE="@every 1h"
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/navidrome/data` → `/data`
- `${FILES_BASE_DIR}/navidrome/music` → `/music:ro`

---

## Phase 3: Core Services (`docker-compose.core.yml`)

### [ ] 3.1 Vaultwarden (Bitwarden Alternative)
**Image:** `vaultwarden/server:latest`  
**Profile:** `core`

> Note: Using Vaultwarden (community implementation) instead of official Bitwarden for easier self-hosting

#### .env Variables to Add:
```env
# =============================================================================
# SECURITY SERVICES CONFIGURATION (Profile: core)
# =============================================================================

# Vaultwarden - Password Manager (Bitwarden Compatible)
VAULTWARDEN_PORT=8089
VAULTWARDEN_MEMORY_LIMIT=512m
VAULTWARDEN_TRAEFIK_ENABLE=true
VAULTWARDEN_DOMAIN=vault.${BASE_DOMAIN}
VAULTWARDEN_PROTOCOL=https
VAULTWARDEN_ADMIN_TOKEN=vaultwarden-admin-token-change-me-2024
VAULTWARDEN_SIGNUPS_ALLOWED=false
VAULTWARDEN_INVITATIONS_ALLOWED=true
VAULTWARDEN_SHOW_PASSWORD_HINT=false
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/vaultwarden/data` → `/data`

#### Security Notes:
- Set `SIGNUPS_ALLOWED=false` after initial setup
- Admin panel accessible at `/admin` with token
- Requires HTTPS for browser extensions

---

## Phase 4: Automation Services (`docker-compose.automation.yml`)

### [ ] 4.1 Home Assistant
**Image:** `ghcr.io/home-assistant/home-assistant:stable`  
**Profile:** `automation`

#### .env Variables to Add:
```env
# =============================================================================
# HOME AUTOMATION CONFIGURATION (OPTIONAL - Profile: automation)
# =============================================================================

# Home Assistant - Home Automation Platform
HOMEASSISTANT_PORT=8123
HOMEASSISTANT_MEMORY_LIMIT=2g
HOMEASSISTANT_TRAEFIK_ENABLE=true
HOMEASSISTANT_DOMAIN=home.${BASE_DOMAIN}
HOMEASSISTANT_PROTOCOL=https
HOMEASSISTANT_CONFIG_DIR=${FILES_BASE_DIR}/homeassistant/config
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/homeassistant/config` → `/config`
- `/etc/localtime` → `/etc/localtime:ro`

#### Special Requirements:
- May need `network_mode: host` for device discovery
- Consider `privileged: true` for USB device access (Zigbee/Z-Wave)
- Add `devices` section for USB dongles if needed

---

## Phase 5: Networking Services (`docker-compose.networking.yml`)

### [ ] 5.1 Rename and Restructure File
- Rename from `docker-compose.traefik.yml`
- Keep existing Traefik and Cloudflare tunnel services
- Add Pi-Hole service

### [ ] 5.2 Pi-Hole - Network-wide Ad Blocking
**Image:** `pihole/pihole:latest`  
**Profile:** `networking`

#### .env Variables to Add:
```env
# =============================================================================
# NETWORK SERVICES CONFIGURATION (Profile: networking)
# =============================================================================

# Pi-Hole - Network-wide Ad Blocking
PIHOLE_PORT_WEB=8088
PIHOLE_PORT_DNS=53
PIHOLE_MEMORY_LIMIT=512m
PIHOLE_TRAEFIK_ENABLE=true
PIHOLE_DOMAIN=pihole.${BASE_DOMAIN}
PIHOLE_PROTOCOL=https
PIHOLE_WEBPASSWORD=pihole-admin-password-2024
PIHOLE_TIMEZONE=${TIMEZONE:-UTC}
PIHOLE_DNS1=1.1.1.1
PIHOLE_DNS2=1.0.0.1
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/pihole/etc-pihole` → `/etc/pihole`
- `${FILES_BASE_DIR}/pihole/etc-dnsmasq.d` → `/etc/dnsmasq.d`

#### Port Mappings:
- `53:53/tcp` - DNS TCP
- `53:53/udp` - DNS UDP
- `${PIHOLE_PORT_WEB}:80` - Web interface

#### Notes:
- May conflict with systemd-resolved on Linux (port 53)
- Consider using `network_mode: host` for DNS

---

## Phase 6: Development Services (`docker-compose.dev.yml`)

### [ ] 6.1 GitLab CE - Complete DevOps Platform
**Image:** `gitlab/gitlab-ce:latest`  
**Profile:** `dev`

> Note: GitLab is resource-intensive. Consider if Gitea meets your needs.

#### .env Variables to Add:
```env
# GitLab CE - DevOps Platform
GITLAB_PORT_HTTP=8929
GITLAB_PORT_SSH=2224
GITLAB_MEMORY_LIMIT=8g
GITLAB_TRAEFIK_ENABLE=true
GITLAB_DOMAIN=gitlab.${BASE_DOMAIN}
GITLAB_PROTOCOL=https
GITLAB_ROOT_PASSWORD=secure_gitlab_password_2024
GITLAB_SHARED_RUNNERS_TOKEN=gitlab-runner-token-2024
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/gitlab/config` → `/etc/gitlab`
- `${FILES_BASE_DIR}/gitlab/logs` → `/var/log/gitlab`
- `${FILES_BASE_DIR}/gitlab/data` → `/var/opt/gitlab`

#### Resource Warning:
- Minimum 4GB RAM recommended, 8GB+ for comfortable operation
- Initial startup can take 5-10 minutes
- Consider SSD storage for better performance

---

## Phase 7: Productivity Services (`docker-compose.productivity.yml`)

### [ ] 7.1 Focalboard - Project Management
**Image:** `mattermost/focalboard:latest`  
**Profile:** `productivity`

> Note: Alternative to Trello/Notion boards

#### .env Variables to Add:
```env
# Focalboard - Project Management (Kanban)
PRODUCTIVITY_FOCALBOARD_PROFILE=productivity
FOCALBOARD_PORT=8086
FOCALBOARD_MEMORY_LIMIT=1g
FOCALBOARD_TRAEFIK_ENABLE=true
FOCALBOARD_DOMAIN=boards.${BASE_DOMAIN}
FOCALBOARD_PROTOCOL=https
FOCALBOARD_DBNAME=focalboard
FOCALBOARD_DBUSER=focalboard
FOCALBOARD_DBPASS=focalboard_password_2024
```

#### Volume Mounts:
- `${FILES_BASE_DIR}/focalboard/data` → `/data`

---

## Phase 8: Documentation & Testing

### [ ] 8.1 Update README.md
- Add new services to available profiles
- Document new environment variables
- Add quick start examples for new profiles

### [ ] 8.2 Update .env.example
- Add all new environment variables with sensible defaults
- Add comments explaining each service

### [ ] 8.3 Create Directory Structure
```bash
mkdir -p files/{immich/{upload,external},kavita/{config,data},navidrome/{data,music}}
mkdir -p files/{vaultwarden/data,homeassistant/config}
mkdir -p files/{pihole/{etc-pihole,etc-dnsmasq.d}}
mkdir -p files/{gitlab/{config,logs,data},focalboard/data}
```

### [ ] 8.4 Test Each Service
- [ ] Test media profile: `docker compose --profile media up -d`
- [ ] Test automation profile: `docker compose --profile automation up -d`
- [ ] Test networking profile: `docker compose --profile networking up -d`
- [ ] Test all together: `docker compose --profile all up -d`

---

## Implementation Order (Recommended)

1. **Phase 1** - File structure changes (required first)
2. **Phase 5** - Networking (Pi-Hole) - simple addition to existing file
3. **Phase 3** - Core (Vaultwarden) - simple single-container service
4. **Phase 7** - Productivity (Focalboard) - extends existing file
5. **Phase 4** - Automation (Home Assistant) - new file, single service
6. **Phase 2** - Media services - new file, multiple services
7. **Phase 6** - Development (GitLab) - resource intensive, test last
8. **Phase 8** - Documentation and testing

---

## Port Allocation Summary

| Service | Port | Notes |
|---------|------|-------|
| Immich | 2283 | Photo/Video management |
| Kavita | 5000 | Digital library |
| Navidrome | 4533 | Music streaming |
| Vaultwarden | 8089 | Password manager |
| Home Assistant | 8123 | Home automation |
| Pi-Hole Web | 8088 | Ad blocking admin |
| Pi-Hole DNS | 53 | DNS server |
| GitLab HTTP | 8929 | DevOps platform |
| GitLab SSH | 2224 | Git SSH access |
| Focalboard | 8086 | Project management |

---

## Checklist Summary

- [ ] Phase 1: File Structure Changes
  - [ ] 1.1 Rename traefik → networking
  - [ ] 1.2 Create media compose file
  - [ ] 1.3 Create automation compose file
  - [ ] 1.4 Update main compose file
- [ ] Phase 2: Media Services
  - [ ] 2.1 Immich
  - [ ] 2.2 Kavita
  - [ ] 2.3 Navidrome
- [ ] Phase 3: Core Services
  - [ ] 3.1 Vaultwarden
- [ ] Phase 4: Automation Services
  - [ ] 4.1 Home Assistant
- [ ] Phase 5: Networking Services
  - [ ] 5.1 Rename file
  - [ ] 5.2 Pi-Hole
- [ ] Phase 6: Development Services
  - [ ] 6.1 GitLab CE
- [ ] Phase 7: Productivity Services
  - [ ] 7.1 Focalboard
- [ ] Phase 8: Documentation & Testing
  - [ ] 8.1 Update README.md
  - [ ] 8.2 Update .env.example
  - [ ] 8.3 Create directories
  - [ ] 8.4 Test services

---

## Notes

- All services follow the established pattern with Traefik labels
- Resource limits are configurable via `.env`
- Consider storage requirements for media services (Immich, Kavita, Navidrome)
- GitLab requires significant resources - evaluate if Gitea is sufficient
- Pi-Hole may conflict with existing DNS services on port 53
