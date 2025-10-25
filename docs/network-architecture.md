# Network Architecture

## Current Network Design (October 2025)

The stack uses a multi-network architecture with a shared external network for cross-service communication and external routing.

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    External Internet                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                 Cloudflare Tunnel                           │
│             *.weekendcodeproject.dev                        │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Traefik                                  │
│              (Reverse Proxy)                                │
│                                                             │
│  ┌─traefik-network─┐         ┌─shared-network─┐            │
│  │   traefik       │◄────────┤  (external)    │            │
│  │   tunnel        │         │                │            │
│  └─────────────────┘         └─┬──────────────┘            │
└─────────────────────────────────┼─────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────┐
│                 Service Networks                            │
│                                                             │
│  ┌─coder-network──┐  ┌─productivity-network─┐  ┌─ai-network─┐│
│  │ • coder        │  │ • nocodb             │  │ • open-webui││
│  │ • gitea        │  │ • paperless-ngx      │  │ • searxng   ││
│  │ • registry     │  │ • n8n                │  │             ││
│  │ • databases    │  │ • databases          │  │             ││
│  └────────┬───────┘  └────────┬─────────────┘  └─────┬───────┘│
│           │                   │                      │        │
│           └───────────────────┼──────────────────────┘        │
│                               │                               │
│                    ┌─shared-network─┐                         │
│                    │  (external)    │                         │
│                    │ Cross-service   │                         │
│                    │ communication   │                         │
│                    └─────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

## Network Details

### **shared-network** (External)
- **Purpose**: Cross-service communication and external routing
- **Type**: Bridge network (external: true)
- **Created**: Manually via `docker network create shared-network`
- **Connected Services**: All services that need external access

### **Service-Specific Networks**

#### **traefik-network**
- **Services**: Traefik, Cloudflare tunnel
- **Purpose**: Isolated proxy infrastructure
- **External Access**: Yes (HTTP/HTTPS ports)

#### **coder-network** 
- **Services**: Coder, Gitea, Registry, PostgreSQL databases
- **Purpose**: Development environment isolation
- **External Access**: Via Traefik + shared-network

#### **productivity-network**
- **Services**: NocoDB, Paperless-ngx, N8N, PostgreSQL + Redis databases  
- **Purpose**: Productivity service isolation
- **External Access**: Via Traefik + shared-network

#### **ai-network**
- **Services**: Open WebUI, SearXNG
- **Purpose**: AI service isolation
- **External Access**: Via Traefik + shared-network
- **External Dependencies**: Native Ollama (host.docker.internal:11434)

## External Routing

### **Domain Mapping**
All subdomains route through the same tunnel:

| Subdomain | Service | Network Path |
|-----------|---------|--------------|
| `coder.weekendcodeproject.dev` | Coder IDE | Tunnel → Traefik → shared-network → coder-network |
| `chat.weekendcodeproject.dev` | Open WebUI | Tunnel → Traefik → shared-network → ai-network |
| `gitea.weekendcodeproject.dev` | Gitea | Tunnel → Traefik → shared-network → coder-network |
| `n8n.weekendcodeproject.dev` | N8N | Tunnel → Traefik → shared-network → productivity-network |
| `nocodb.weekendcodeproject.dev` | NocoDB | Tunnel → Traefik → shared-network → productivity-network |
| `paperless.weekendcodeproject.dev` | Paperless | Tunnel → Traefik → shared-network → productivity-network |
| `search.weekendcodeproject.dev` | SearXNG | Tunnel → Traefik → shared-network → ai-network |

### **Traefik Configuration**
Each service defines routing labels:
```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.service.rule=Host(`service.weekendcodeproject.dev`)
  - traefik.http.routers.service.entrypoints=web,websecure
  - traefik.http.routers.service.tls=true
  - traefik.http.services.service.loadbalancer.server.port=XXXX
  - traefik.docker.network=shared-network
```

### **Tunnel Configuration** (`config/cloudflare/config.yml`)
```yaml
ingress:
  - hostname: "*.weekendcodeproject.dev"
    service: https://traefik:443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

## Security Considerations

### **Network Isolation**
- Services in different networks cannot communicate directly
- Only services connected to shared-network can be reached externally
- Database networks are isolated within service groups

### **TLS Termination**
- External traffic: TLS terminated at Cloudflare
- Internal traffic: TLS terminated at Traefik  
- Service-to-service: Unencrypted (isolated networks)

### **Access Control**
- Local access: Direct port access (no authentication)
- External access: Through tunnel + Traefik only
- Database access: Internal networks only

## Monitoring & Debugging

### **Network Inspection**
```bash
# List all networks
docker network ls

# Inspect shared network
docker network inspect shared-network

# Check service connectivity
docker exec coder ping nocodb
docker exec traefik nslookup coder
```

### **Traefik Dashboard**
Monitor routing at: http://localhost:8083/dashboard/
- Service discovery status
- Routing rules
- Health checks
- Request metrics

### **Common Issues**

#### **Service Not Reachable Externally**
1. Check service is connected to shared-network
2. Verify Traefik labels are correct
3. Confirm Traefik can reach service
4. Test tunnel connectivity

#### **Cross-Service Communication Failed**
1. Ensure both services are on shared-network
2. Use service names (not localhost) for internal calls
3. Check Docker DNS resolution

#### **Database Connection Issues**
1. Verify database and service are on same network
2. Check healthcheck status
3. Confirm connection string uses service name

## Performance Considerations

### **Network Overhead**
- Multiple networks add minimal overhead
- Shared-network enables efficient cross-service communication
- Local service-to-service traffic bypasses external routing

### **Scaling Considerations**
- Each service group can be scaled independently
- Shared-network supports service discovery
- Database connections pooled within service networks

### **Resource Usage**
- Docker networks are lightweight
- No performance impact for isolated services
- Traefik adds ~1-2ms latency for external requests