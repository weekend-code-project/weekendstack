# Stack Fixes Log

> **Purpose**: Document live stack fixes so they can later be applied to the setup script.
> Each entry describes what broke, what the root cause was, and how to prevent it at setup time.

---

## Fix #1 — Coder Not Accessible via Cloudflare Tunnel (coder.weekendcodeproject.dev)

**Date**: 2026-03-15  
**Symptom**: `coder.weekendcodeproject.dev` unreachable through the Cloudflare tunnel. Traefik had no coder routes registered despite the container running.

### Root Cause Chain

1. **Disk full (100%)** — Docker image cache and build cache had consumed all 124 GB.
2. **PostgreSQL (`coder-database`) crashed** — At 09:22 UTC it logged `FATAL: could not write init file` and eventually exited. This happened because the disk was full and Postgres couldn't write WAL/init files.
3. **Coder lost DB connection** — At 09:32 UTC coder logged `pubsub disconnected from postgres … no such host` as its Docker network state also degraded (no IP assigned on shared-network / coder-network).
4. **Traefik skips unhealthy containers** — Traefik v3 does NOT register routes for containers whose Docker healthcheck is not in the `healthy` state. Because coder's healthcheck (`curl http://localhost:7080/healthz`) was failing (no DB connection → empty reply), Traefik silently dropped all six coder routers.

### Live Fix Applied

```bash
# 1. Free disk space (64 GB of unused images + 1.5 GB build cache)
docker builder prune -af
docker image prune -af
# Result: ~55 GB freed

# 2. Restart the crashed database
docker restart coder-database
# Wait for: running healthy

# 3. Restart coder (now DB is available, healthcheck passes)
docker restart coder
# Wait for: running healthy

# 4. Verify Traefik picked up the 6 coder routes
curl -s "http://localhost:8081/api/http/routers?per_page=200" | \
  python3 -c "import json,sys; r=json.load(sys.stdin); \
  [print(x['name']) for x in r if 'coder' in x['name'].lower()]"
# Expected output: 6 coder-* routers all 'enabled'

# 5. Verify end-to-end
curl -sk --resolve "coder.weekendcodeproject.dev:443:127.0.0.1" \
  -o /dev/null -w "%{http_code}" https://coder.weekendcodeproject.dev/
# Expected: 200
```

### Setup Script Changes Needed

| Location | Change |
|---|---|
| `setup.sh` / post-install | Add a **disk space pre-flight check** — warn/abort if available disk is below a threshold (e.g. 10 GB) before starting the stack. |
| `setup.sh` / post-install | After `docker compose up -d`, **run `docker system prune -f`** to clear dangling images from the install itself. |
| `compose/docker-compose.dev.yml` | Consider adding `restart: on-failure` or a dependency restart policy for `coder` so it recovers automatically if `coder-database` dies and comes back. |
| Documentation | Add a "Disk Management" section to `docs/deployment-guide.md` noting that 20+ GB free is needed for stable operation and explaining how to prune Docker. |

### Key Insight for Traefik + Docker Health Checks

**Traefik v3 will not register routes for any container that has a Docker `healthcheck` defined but is not in the `healthy` state.** This is silent — no error in the API or logs. To diagnose: check `docker inspect <container> --format '{{.State.Health.Status}}'`. If it's `starting` or `unhealthy`, Traefik won't see it even if `traefik.enable=true` is set.

---

<!-- Add future fixes below this line in the same format -->
