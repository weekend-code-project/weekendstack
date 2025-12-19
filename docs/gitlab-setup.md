# GitLab Setup

GitLab CE provides a complete DevOps platform including Git repository hosting, CI/CD pipelines, issue tracking, and more.

## Access

**Use the HTTPS URL even from your local network:**
- **Recommended:** https://gitlab.weekendcodeproject.dev

GitLab's authentication and session management requires HTTPS to function properly. While the container is accessible on port 8929 locally, attempting to use it via HTTP will fail during login due to HTTPS redirects in the application logic.

The Cloudflare tunnel URL works from anywhere (local network or internet) and provides the proper HTTPS experience GitLab expects.

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
