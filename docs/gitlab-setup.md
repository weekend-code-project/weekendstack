# GitLab Setup

GitLab CE provides a complete DevOps platform including Git repository hosting, CI/CD pipelines, issue tracking, and more.

## ⚠️ HTTPS Required

**GitLab requires HTTPS** for the web interface to function properly. The WebCrypto API used by GitLab is only available in secure contexts (HTTPS or localhost).

**You must access GitLab via the Cloudflare tunnel:**
- ✅ https://gitlab.weekendcodeproject.dev (works)
- ❌ http://192.168.2.50:8929 (will not work from remote machines)

The local HTTP URL will only work if you're accessing from the Docker host itself via `http://localhost:8929`.

## Configuration

GitLab is configured in `docker-compose.dev.yml` with the `gitlab` profile.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GITLAB_HTTP_PORT` | 8929 | Local HTTP port |
| `GITLAB_SSH_PORT` | 2224 | SSH port for Git operations |
| `GITLAB_CONFIG_DIR` | ./files/gitlab/config | GitLab configuration |
| `GITLAB_LOGS_DIR` | ./files/gitlab/logs | Log files |
| `GITLAB_DATA_DIR` | ./files/gitlab/data | Repository and database data |
| `GITLAB_MEMORY_LIMIT` | 4g | Memory limit (4GB minimum recommended) |

## Starting GitLab

```bash
docker compose --profile gitlab up -d
```

GitLab takes **3-5 minutes** to fully initialize on first start.

## Access

| Type | URL | Notes |
|------|-----|-------|
| Public (recommended) | https://gitlab.weekendcodeproject.dev | Full functionality |
| Local (Docker host only) | http://localhost:8929 | Only works on the server itself |

## Initial Root Password

After GitLab is healthy, retrieve the initial root password:

```bash
docker exec gitlab cat /etc/gitlab/initial_root_password
```

Login with:
- **Username:** root
- **Password:** (from command above)

> ⚠️ The initial password file is automatically deleted after 24 hours. Change the root password immediately.

## Troubleshooting

### Chrome Redirects HTTP to HTTPS

If Chrome automatically redirects `http://192.168.2.50:8929` to HTTPS, it's due to HSTS (HTTP Strict Transport Security) caching from accessing GitLab through the Cloudflare tunnel.

**Fix:**
1. Open `chrome://net-internals/#hsts`
2. Scroll to "Delete domain security policies"
3. Enter `192.168.2.50` and click **Delete**

**Alternative:** Use an incognito window which doesn't have cached HSTS policies.

### GitLab Won't Start

Check logs:
```bash
docker logs gitlab
```

Common issues:
- **Port conflict:** Ensure ports 8929 and 2224 are not in use
- **Memory:** GitLab requires at least 4GB RAM
- **Permissions:** Docker will create directories automatically

### Health Check Status

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep gitlab
```

GitLab will show `(health: starting)` during initialization and `(healthy)` when ready.

## Resource Requirements

- **RAM:** 4GB minimum, 8GB recommended
- **CPU:** 2 cores minimum
- **Disk:** 10GB+ for installation, more for repositories

## SSH Access

GitLab SSH is available on port 2224 (to avoid conflict with Gitea on 2222).

Configure SSH in `~/.ssh/config`:
```
Host gitlab-local
    HostName 192.168.2.50
    Port 2224
    User git
```

Then clone with:
```bash
git clone gitlab-local:username/repo.git
```
