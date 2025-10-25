# Deployment & Management Guide

## Quick Deployment

### Prerequisites
- Docker & Docker Compose installed
- 8GB+ RAM recommended
- 50GB+ disk space for services and data

### Initial Setup
```bash
# Clone the repository
git clone https://github.com/jessefreeman/wcp-coder.git
cd wcp-coder

# Copy environment template
cp .env.example .env

# (Optional) Edit .env for custom settings
# All services work with defaults

# Create external network
docker network create shared-network

# Start the complete stack
docker compose up -d
```

### Verify Deployment
```bash
# Check all services are running
docker compose ps

# Check service health
docker compose logs -f

# Test external access (if configured)
curl -I https://coder.weekendcodeproject.dev
```

## Service Management

### Profile-based Control
```bash
# Start everything (default)
docker compose up -d

# Start specific service groups
docker compose --profile development up -d
docker compose --profile productivity up -d  
docker compose --profile ai up -d

# Stop specific services
docker compose stop coder gitea
docker compose stop nocodb paperless-ngx n8n
```

### Individual Service Control
```bash
# Restart a service
docker compose restart coder

# View service logs
docker compose logs -f coder
docker compose logs -f paperless-ngx

# Scale services (where applicable)
docker compose up -d --scale open-webui=2
```

### Data Management

#### Backup User Data
```bash
# All user data is in ./files/ directory
tar -czf backup-$(date +%Y%m%d).tar.gz ./files/

# Backup specific service data
tar -czf coder-backup.tar.gz ./files/coder/
tar -czf paperless-backup.tar.gz ./files/paperless/
```

#### Backup Database Volumes
```bash
# Stop services first
docker compose stop

# Backup database volumes
docker run --rm -v coder-db-data:/data -v $(pwd):/backup alpine tar czf /backup/coder-db-backup.tar.gz /data
docker run --rm -v paperless-db-data:/data -v $(pwd):/backup alpine tar czf /backup/paperless-db-backup.tar.gz /data

# Restart services
docker compose up -d
```

#### Restore from Backup
```bash
# Stop services
docker compose down

# Restore user data
tar -xzf backup-YYYYMMDD.tar.gz

# Restore database volumes (if needed)
docker volume create coder-db-data
docker run --rm -v coder-db-data:/data -v $(pwd):/backup alpine tar xzf /backup/coder-db-backup.tar.gz -C /

# Restart
docker compose up -d
```

## External Access Setup

### Cloudflare Tunnel Configuration
1. Install cloudflared on your system
2. Create a tunnel: `cloudflared tunnel create wcp-coder`
3. Place credentials in `config/cloudflare/.cloudflared/`
4. Update `config/cloudflare/config.yml` with your tunnel ID
5. Set DNS records in Cloudflare dashboard

### Domain Configuration
Update `.env` with your domain:
```bash
BASE_DOMAIN=yourdomain.com
CODER_DOMAIN=coder.yourdomain.com
```

Services will be available at:
- `coder.yourdomain.com`
- `chat.yourdomain.com`
- `gitea.yourdomain.com`
- etc.

## Troubleshooting

### Common Issues

#### Services Won't Start
```bash
# Check logs for errors
docker compose logs service-name

# Common fixes
docker compose down
docker system prune -f
docker compose up -d
```

#### External Access Not Working
```bash
# Check Traefik dashboard
http://localhost:8083/dashboard/

# Verify tunnel status
docker compose logs cloudflare-tunnel

# Test internal routing
curl -H "Host: coder.yourdomain.com" http://localhost:80
```

#### Database Connection Issues
```bash
# Check database health
docker compose ps | grep healthy

# Restart database services
docker compose restart coder-database nocodb-db paperless-db

# Check database logs
docker compose logs coder-database
```

#### Out of Disk Space
```bash
# Clean up Docker
docker system prune -a --volumes

# Check service data usage
du -sh ./files/*
du -sh ./config/*

# Clean up old logs
docker compose logs --since 24h > /dev/null
```

### Performance Tuning

#### Memory Optimization
Edit `.env` to adjust memory limits:
```bash
CODER_MEMORY_LIMIT=1g
NOCODB_MEMORY_LIMIT=512m
PAPERLESS_MEMORY_LIMIT=1g
```

#### Database Tuning
For high-usage scenarios, consider:
- Dedicated database servers
- SSD storage for database volumes
- Increased connection limits

## Monitoring

### Service Health
```bash
# Check all service status
docker compose ps

# Monitor resource usage
docker stats

# View service logs
docker compose logs -f --tail=100
```

### Traefik Dashboard
Access at http://localhost:8083/dashboard/ to monitor:
- Service routing
- Request metrics
- Health status
- SSL certificates

### Log Aggregation
For production use, consider:
- Centralized logging (ELK stack)
- Log rotation policies
- Alerting on service failures

## Security Considerations

### Access Control
- Change default passwords in `.env`
- Use strong credentials for databases
- Enable service-specific authentication where available

### Network Security
- Services isolated in separate networks
- External access only through Traefik
- TLS encryption for all external traffic

### Data Protection
- Regular backups of `./files/` directory
- Database volume backups
- Secure storage of Cloudflare tunnel credentials

## Updates & Maintenance

### Updating Services
```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d

# Clean up old images
docker image prune
```

### Configuration Updates
```bash
# After editing docker compose files
docker compose up -d --force-recreate service-name

# After editing .env
docker compose down
docker compose up -d
```

### Regular Maintenance
- Weekly: Check service logs for errors
- Monthly: Update container images
- Quarterly: Review resource usage and optimize