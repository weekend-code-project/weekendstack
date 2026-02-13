# Stack Architecture Overview

## Current Architecture (October 2025)

### **Service Organization**
This stack is organized into modular Docker Compose files with shared networking for external access:

```
docker-compose.yml          # Main orchestration file
compose/
├── docker-compose.dev.yml         # Development services (Coder, Gitea)
├── docker-compose.productivity.yml # Productivity services (NocoDB, Paperless, N8N) 
├── docker-compose.ai.yml           # AI services (Open WebUI, SearXNG)
├── docker-compose.networking.yml  # Reverse proxy & tunnel
└── docker-compose.core.yml         # Reserved for future infrastructure
```

### **Network Architecture**
```
shared-network (external)           # Cross-service communication & external routing
├── traefik-network                 # Traefik & Cloudflare tunnel
├── coder-network                   # Development services
├── productivity-network            # Productivity services  
└── ai-network                      # AI services
```

### **External Access Flow**
```
Internet → Cloudflare Tunnel → Traefik → Services
```

All `*.weekendcodeproject.dev` domains route through:
1. **Cloudflare tunnel** (config/cloudflare/config.yml)
2. **Traefik reverse proxy** (labels on each service)
3. **Target service** (via shared-network)

## Service Mapping

### **Development Services** (`compose/docker-compose.dev.yml`)
| Service | Local Port | External Domain | Network | Database |
|---------|------------|-----------------|---------|----------|
| Coder IDE | 7080 | coder.weekendcodeproject.dev | coder-network + shared-network | PostgreSQL 16 |
| Gitea | 7001 | gitea.weekendcodeproject.dev | coder-network + shared-network | PostgreSQL 16 |
| Registry Cache | 5001 | - | coder-network | - |

### **Productivity Services** (`compose/docker-compose.productivity.yml`)
| Service | Local Port | External Domain | Network | Database |
|---------|------------|-----------------|---------|----------|
| NocoDB | 8090 | nocodb.weekendcodeproject.dev | productivity-network + shared-network | PostgreSQL 15 |
| Paperless-ngx | 8082 | paperless.weekendcodeproject.dev | productivity-network + shared-network | PostgreSQL 15 + Redis 7 |
| N8N | 5678 | n8n.weekendcodeproject.dev | productivity-network + shared-network | PostgreSQL 15 |

### **AI Services** (`compose/docker-compose.ai.yml`)
| Service | Local Port | External Domain | Network | External Dependency |
|---------|------------|-----------------|---------|-------------------|
| Open WebUI | 3000 | chat.weekendcodeproject.dev | ai-network + shared-network | Native Ollama (host:11434) |
| SearXNG | 4000 | search.weekendcodeproject.dev | ai-network + shared-network | - |

### **Infrastructure Services** (`docker-compose.traefik.yml`)
| Service | Local Port | External Domain | Network | Purpose |
|---------|------------|-----------------|---------|---------|
| Traefik | 80, 443, 8083 | - | traefik-network + shared-network | Reverse proxy & dashboard |
| Cloudflare Tunnel | - | - | traefik-network | Secure external access |

## Data Storage Strategy

### **Database Volumes** (Docker-managed)
```
coder-db-data           # Coder PostgreSQL data
gitea-db-data          # Gitea PostgreSQL data  
nocodb-db-data         # NocoDB PostgreSQL data
n8n-db-data            # N8N PostgreSQL data
paperless-db-data      # Paperless PostgreSQL data
paperless-redis-data   # Paperless Redis data
```

### **User Data** (Bind mounts to `./files/`)
```
./files/
├── coder/
│   ├── templates/     # Coder workspace templates
│   └── workspace/     # User workspace data
├── gitea/app/         # Git repositories & Gitea data
├── nocodb/           # NocoDB user data
├── n8n/              # N8N workflows & credentials
├── paperless/
│   ├── data/         # Paperless application data
│   ├── media/        # Processed documents
│   ├── consume/      # Document intake folder
│   └── export/       # Export destination
├── open-webui/       # Chat history & AI models
├── searxng/          # Search engine settings
└── registry/cache/   # Docker registry cache
```

### **Configuration** (Bind mounts to `./config/`)
```
./config/
├── traefik/
│   ├── config.yml    # Traefik configuration
│   └── auth/         # Authentication files
└── cloudflare/
    ├── config.yml    # Tunnel routing rules
    └── .cloudflared/ # Tunnel credentials
```

## Healthchecks & Dependencies

All database services include healthchecks:
- **PostgreSQL**: `pg_isready` checks every 30s
- **Redis**: `redis-cli ping` checks every 30s
- **Application services**: Wait for healthy database dependencies

## Security & Access

### **Local Development**
- All services accessible via localhost ports
- No authentication required for local access
- Docker socket proxy for secure container management

### **External Access**
- HTTPS-only via Cloudflare tunnel
- TLS termination at Traefik
- Service-specific authentication (where supported)
- Network isolation between service groups

## Resource Limits

Memory limits configured per service via environment variables:
- **Coder**: 2GB (configurable via `CODER_MEMORY_LIMIT`)
- **Databases**: 512MB-1GB each
- **AI Services**: 1-2GB (Open WebUI can be resource-intensive)
- **Other services**: 512MB-2GB based on workload