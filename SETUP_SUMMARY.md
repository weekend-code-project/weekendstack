# WeekendStack Setup Summary

**Setup completed successfully!** 🎉

This document contains important information about your WeekendStack deployment.

---

## Quick Access

### Local Network Access (.lab domain)

Your WeekendStack is accessible on your local network using the `.lab` domain:

**Core Services:**
- [Glance Dashboard](https://lab) - Homepage with widgets
- [Vaultwarden](https://vault.lab) - Password manager
- [Link Router](https://go.lab) - Go links service

**Network Services:**
- [Traefik Dashboard](https://traefik.lab:8081) - Reverse proxy
- [Pi-hole Admin](http://pihole.lab/admin) - DNS and ad blocking

**Development Tools:**
- [Coder](https://coder.lab) - Cloud development environments
- [Gitea](https://gitea.lab) - Git service
- [GitLab](https://gitlab.lab) - Complete DevOps platform


---

## Default Credentials

Many services use these default credentials for initial setup:

- **Username:** `test`
- **Email:** `test@test.com`
- **Password:** ``

⚠️ **IMPORTANT SECURITY NOTICE:**
1. Change default passwords immediately after first login
2. Disable user registration on services after creating your account
3. Review and update all credentials in production environments

### First-Time Setup Services

These services require you to create the first user account (which becomes admin):

- **Open WebUI** - Visit https://open-webui.lab and sign up
- **Immich** - Visit https://immich.lab and create account
- **Mealie** - Visit https://mealie.lab and create account
- **Home Assistant** - Visit https://hass.lab and create account
- **Kavita** - Visit https://kavita.lab and create account
- **Navidrome** - Visit https://navidrome.lab and create account

The first user to register becomes the administrator.

---

## Next Steps

### 1. Trust Local HTTPS Certificate

To avoid browser security warnings:

**Linux (Ubuntu/Debian):**
```bash
sudo cp config/traefik/certs/ca-cert.pem /usr/local/share/ca-certificates/weekendstack-ca.crt
sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain config/traefik/certs/ca-cert.pem
```

**Windows (WSL):**
Import `config/traefik/certs/ca-cert.pem` via Windows certificate manager.

**Browsers:** Restart your browser after installing the certificate.

### 2. Configure DNS

**Option A: Use Pi-hole as DNS**
Set your device DNS to: `192.168.2.160`

**Option B: Edit /etc/hosts (Linux/macOS) or C:\Windows\System32\drivers\etc\hosts (Windows)**
Add entries for each service manually.

### 3. Configure Services

#### Glance Dashboard
Edit `config/glance/glance.yml` to customize your dashboard:
- Add API keys for weather, calendar, RSS feeds
- Configure widgets and layout
- Restart Glance: `docker restart glance`

#### Paperless-ngx
Place documents in: `files/paperless/consume/`
They will be automatically processed and indexed.

#### Coder
Access at https://coder.lab
Create development environments using the templates in `config/coder/templates/`


---

## Maintenance Commands

### Start Services
```bash
docker compose up -d
```

### Stop Services
```bash
docker compose down
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f <service-name>

# Or use Dozzle: https://dozzle.lab
```

### Update Services
```bash
docker compose pull
docker compose up -d
```

### Restart a Service
```bash
docker compose restart <service-name>
```

### Check Service Health
```bash
./tools/test_stack_health.sh
```

### Validate Configuration
```bash
./tools/validate-env.sh
```

---

## File Locations

### User Data (BACKUP THESE!)
- **Documents:** `files/paperless/`
- **Photos:** `files/immich/` (or NFS mount)
- **Music:** `files/navidrome/music/`
- **Books:** `files/kavita/library/`
- **AI Models:** `files/ai-models/ollama/`
- **Workspaces:** `files/coder/workspace/` or ``

### Application Data
- **Databases:** Docker volumes (use `docker volume ls`)
- **Configurations:** `config/`
- **Application state:** `data/`

### Important Configuration Files
- **Environment:** `.env`
- **Traefik:** `config/traefik/config.yml`
- **Cloudflare:** `config/cloudflare/config.yml`
- **Glance:** `config/glance/glance.yml`

---

## Troubleshooting

### Service won't start
1. Check logs: `docker compose logs <service>`
2. Verify .env configuration: `./tools/validate-env.sh`
3. Check for port conflicts: `docker compose ps`

### Cannot access services on .lab domain
1. Verify Pi-hole is running: `docker ps | grep pihole`
2. Check DNS settings on your device (should be 192.168.2.160)
3. Verify dnsmasq config: `cat config/pihole/etc-dnsmasq.d/02-custom-lab.conf`

### Browser shows security warning (HTTPS)
1. Install CA certificate (see "Trust Local HTTPS Certificate" above)
2. Restart browser after installing
3. If still showing, check certificate dates: `openssl x509 -in config/traefik/certs/cert.pem -text`

### Database connection errors
1. Wait for database to be healthy: `docker ps` (check "healthy" status)
2. Check database logs: `docker compose logs <service>-db`
3. Verify credentials in .env match service configuration

### Out of disk space
1. Clean up Docker: `docker system prune -a`
2. Check disk usage: `du -sh files/ data/`
3. Configure log rotation: `docker compose --log-opt max-size=10m`

---

## Documentation

For detailed setup and configuration guides, see:

- **Architecture:** `docs/architecture.md`
- **Network Setup:** `docs/network-architecture.md`
- **Service Guides:** `docs/<service>-setup.md`
- **Credentials:** `docs/credentials-guide.md`
- **File Paths:** `docs/file-paths-reference.md`

---

## Support & Community

- **Documentation:** `docs/` directory
- **Issues:** Check service-specific logs and documentation
- **Updates:** Run `docker compose pull` regularly

---

**Generated:** 2026-02-14 13:27:06
**Profiles:** core networking dev
**Setup Script:** WeekendStack v1.0
