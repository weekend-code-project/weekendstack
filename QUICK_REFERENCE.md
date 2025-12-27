# Quick Reference - Service Access

## ✅ All Systems Operational
**Tested:** December 27, 2025  
**Status:** 38/38 accessible services working (100%)

## Access the Dashboard

**Primary:** http://192.168.2.50  
**Alternative:** http://home.lab (requires Pi-hole DNS)

## Access Any Service (3 Methods)

### 1. Direct IP:Port (Fastest, No DNS Required)
```
http://192.168.2.50:7080  ← Coder
http://192.168.2.50:7001  ← Gitea
http://192.168.2.50:8090  ← NocoDB
http://192.168.2.50:5678  ← n8n
http://192.168.2.50:2283  ← Immich
... see full list in SERVICE_TEST_RESULTS.md
```

### 2. Smart Links (Click in Glance)
- Auto-detects your entry point
- From IP → redirects to `http://192.168.2.50:PORT`
- From .lab → redirects to `http://service.lab`

### 3. .lab Domains (Requires Pi-hole)
```
http://coder.lab
http://gitea.lab
http://nocodb.lab
http://n8n.lab
... etc
```

## Common Services Quick Access

| Service | Direct URL | .lab Domain |
|---------|-----------|-------------|
| Coder | http://192.168.2.50:7080 | http://coder.lab |
| Gitea | http://192.168.2.50:7001 | http://gitea.lab |
| NocoDB | http://192.168.2.50:8090 | http://nocodb.lab |
| n8n | http://192.168.2.50:5678 | http://n8n.lab |
| Paperless | http://192.168.2.50:8082 | http://paperless.lab |
| Immich | http://192.168.2.50:2283 | http://immich.lab |
| Portainer | http://192.168.2.50:9000 | http://portainer.lab |
| Pi-hole | http://192.168.2.50:8088/admin | http://pihole.lab/admin |
| Uptime Kuma | http://192.168.2.50:3001 | http://uptime-kuma.lab |

## Services Requiring Special Setup

**GitLab & Vaultwarden:** Require HTTPS (not configured for local HTTP)  
**Traefik Dashboard:** http://traefik.lab (only via .lab domain)  
**Coder Registry:** No web UI (Docker registry API only)

## Troubleshooting

**"Connection refused"?**
- Check if service is running: `docker ps | grep service-name`
- Verify port mapping: `docker port service-name`

**"Page not loading"?**
- Try direct IP:port first (method #1)
- If that works, DNS issue - use IP:port instead of .lab

**"404 Not Found"?**
- Check port number in SERVICE_TEST_RESULTS.md
- Some services need paths (e.g., Pi-hole needs /admin)

**Smart links not working?**
- Verify you're accessing via Traefik (port 80, not 8080)
- Check link-router is running: `docker ps | grep link-router`

## Test All Services

Run comprehensive test:
```bash
cd /opt/stacks/weekendstack
./comprehensive_test.sh
```

## Documentation

- **[SERVICE_TEST_RESULTS.md](SERVICE_TEST_RESULTS.md)** - Complete service matrix with all 41 services
- **[COMPREHENSIVE_TEST_SUMMARY.md](COMPREHENSIVE_TEST_SUMMARY.md)** - Detailed testing report with all fixes
- **[comprehensive_test.sh](comprehensive_test.sh)** - Automated test script

---

**Last Updated:** December 27, 2025  
**Test Status:** ✅ All 38 accessible services verified working
