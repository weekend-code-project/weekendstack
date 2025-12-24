# Stack Improvements — Implementation Plan

Created: 2025-12-24  
Status: In progress  
Baseline tag: `v2025.12.24`

## Overview
This document tracks the implementation work for:
- Adding **Glance** (new dashboard)
- Adding **File Browser** (scoped to the repo `files/` directory)
- Adding **Hoarder** (bookmark-everything)
- Fixing **`*.lab` routing** issues for existing services
- **Deprioritizing Personal** services (disable by default; don’t delete compose)
- **Local HTTPS** improvements (explicitly last)

## Goals
1. Add Glance, File Browser, Hoarder in a way that matches the stack’s “turn-key” profile model.
2. Make `*.lab` access predictable (services that are running should route on `http://<svc>.lab`).
3. Keep monitoring services as-is for now (evaluate overlap later).
4. Defer local HTTPS until the end.

## Non-goals
- Removing monitoring services (we’ll only mark candidates for later)
- Implementing local HTTPS in Phase 3 (explicitly last)

## Workstreams
| Workstream | Priority | Target files | Depends on | Status |
|---|---:|---|---|---|
| Glance | P0 | `docker-compose.core.yml`, `config/glance/*` | Traefik running | Done |
| File Browser (scoped to `files/`) | P0 | `docker-compose.productivity.yml` | Traefik running | Done |
| Hoarder | P0 | `docker-compose.productivity.yml` | Meilisearch + Chrome | Done |
| Fix `*.lab` routing for existing services | P0 | `docker-compose.*.yml` + env vars | Services running | In progress |
| Disable personal by default (don’t delete) | P1 | `docker-compose.personal.yml` (+ docs) | none | Done |
| Monitoring consolidation (later) | P2 | `docker-compose.monitoring.yml` | needs evaluation | Not started |
| Local HTTPS (last) | P3 | `config/traefik/*`, `docker-compose.networking.yml` | decisions + tokens | Not started |

---

## Phase 1 — Add services + fix `.lab` (no local HTTPS yet)

### 1) Glance
**Current state**: Homer is the dashboard.

**Desired state**:
- Glance available on `http://glance.lab`
- (Optional later) `https://glance.${BASE_DOMAIN}`

**Checklist**
- [x] Add `glance` service to `docker-compose.core.yml`
- [x] Add minimal `config/glance/glance.yml`
- [x] Add Traefik routers: `glance.lab` (HTTP)
- [ ] Validate: `curl -I http://glance.lab`

**Rollback**
- Remove `glance` service + config directory

### 2) File Browser (scoped to `files/`)
**Desired state**:
- File Browser serves only the repo `files/` directory (no host root mounts)
- Available at `http://filebrowser.lab`

**Checklist**
- [x] Add `filebrowser` service to `docker-compose.productivity.yml`
- [x] Mount `./files` → `/srv` only
- [x] Persist File Browser config in a volume (not inside `./files`)
- [ ] Validate: browse, upload a test file, confirm it appears under `files/`

**Rollback**
- Remove service and its named volume

### 3) Hoarder
**Desired state**:
- Hoarder available at `http://hoarder.lab`
- Data persisted

**Checklist**
- [x] Add hoarder stack services + storage
- [x] Add Traefik routers: `hoarder.lab` (HTTP)
- [ ] Set secrets in env (`HOARDER_NEXTAUTH_SECRET`, `HOARDER_MEILI_MASTER_KEY`)
- [ ] Validate: create a bookmark, verify persistence after restart

**Rollback**
- Remove services and volumes

### 4) Fix `*.lab` issues for existing services
**Known issues reported**:
- Not coming up under `*.lab`: gitea, immich, activepieces, docmost, n8n, nocodb, paperless, postiz, vaultwarden (vaultwarden loads only over HTTPS)
- Excalidraw “needs auth” (likely external policy)

**Approach**:
- Ensure services use consistent profile names (e.g., `dev` vs `development`).
- Ensure each service that should be reachable on `.lab` has a `web` router Host(`<svc>.lab`).
- For apps that hard-require HTTPS (secure cookies / WebCrypto), note exceptions until Phase 3.

**Checklist**
- [x] Fix `dev` vs `development` profile mismatch in dev compose (Gitea stack)
- [ ] Confirm productivity services are started when expected
- [ ] Document which apps do not work on plain HTTP (`vaultwarden`, many NextAuth apps)

---

## Phase 2 — Disable Personal by default
**Desired state**:
- Personal services exist, but are not started under the default `all` profile.

**Checklist**
- [x] Remove `all` profile from personal services (keep `personal`)
- [ ] Update README note: to run personal services, use `--profile personal`

---

## Phase 3 — Local HTTPS (last)
**Decision point**:
- Option A (recommended): wildcard `*.${BASE_DOMAIN}` via Cloudflare DNS-01 with Traefik; split-horizon DNS for LAN
- Option B: private wildcard `*.lab` cert (mkcert/step-ca) loaded into Traefik; requires client trust installs

**Checklist**
- [ ] Pick A or B
- [ ] Implement Traefik TLS config and persistence
- [ ] Validate Vaultwarden and NextAuth-based apps work under HTTPS
