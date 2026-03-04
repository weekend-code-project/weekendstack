# Supabase Template

A full Supabase local development workspace using Docker-in-Docker with the official Supabase CLI.

## Features

- **Full Supabase Stack** — Postgres, Studio, Auth, PostgREST, Realtime, Storage (managed by `supabase start`)
- **Supabase Studio** — dashboard accessible via Coder's local preview (port 54323)
- **Supabase CLI** — pre-installed for migrations, edge functions, testing, and type generation
- **psql CLI** — pre-installed for direct database access
- **Docker-in-Docker** — Supabase services run as containers inside the workspace
- **Code-server** — VS Code in the browser
- **SSH access** — optional, with configurable password
- **App Preview** — configurable port for your web application

## Quick Start

1. Create a workspace from this template
2. Wait for Supabase to finish starting (first run pulls images, takes a few minutes)
3. Click **Supabase Studio** from the workspace dashboard
4. Use the Table Editor to create tables, or the SQL Editor for queries
5. Your REST API is auto-available at `localhost:54321`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| App Preview Port | Port for your web app | 8080 |
| External Preview | Enable Traefik external routing | true |
| Enable SSH | Start SSH server | true |
| Git Platform CLI | Install gh, glab, or tea | none |

## Supabase Ports (inside workspace)

| Service | Port | Purpose |
|---------|------|---------|
| API | 54321 | PostgREST auto-generated REST API |
| DB | 54322 | Direct PostgreSQL connection |
| Studio | 54323 | Supabase dashboard |
| Auth | 54321 | GoTrue (via API gateway) |
| Realtime | 54321 | WebSocket subscriptions |
| Storage | 54321 | S3-compatible file storage |

## CLI Usage

```bash
# Check status
supabase status

# Create a migration
supabase migration new my_table

# Run migrations
supabase db reset

# Generate TypeScript types
supabase gen types typescript --local > types/supabase.ts

# Start/stop
supabase stop
supabase start

# Connect via psql
psql postgresql://postgres:postgres@localhost:54322/postgres
```

## Architecture

```
┌──────────────────────────────────────────────┐
│  Privileged Workspace Container (DinD)       │
│  ┌────────────────────────────────────────┐  │
│  │ code-server, supabase CLI, psql        │  │
│  │ Port 8080 (your app)                   │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌─ Docker-in-Docker ────────────────────┐   │
│  │  supabase start manages:              │   │
│  │  ┌──────────┐ ┌──────────┐ ┌───────┐ │   │
│  │  │ Postgres │ │ PostgREST│ │ Auth  │ │   │
│  │  │ :54322   │ │ :54321   │ │       │ │   │
│  │  └──────────┘ └──────────┘ └───────┘ │   │
│  │  ┌──────────┐ ┌──────────┐ ┌───────┐ │   │
│  │  │ Studio   │ │ Realtime │ │Storage│ │   │
│  │  │ :54323   │ │          │ │       │ │   │
│  │  └──────────┘ └──────────┘ └───────┘ │   │
│  └───────────────────────────────────────┘   │
│  Volume: docker_data (persists images)       │
└──────────────────────────────────────────────┘
```
