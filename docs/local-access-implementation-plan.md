# Implementation Plan: Dual-Domain Routing for Weekend Stack

## Overview

Enable all Weekend Stack services to be accessible via two domains:
- **Public:** `*.weekendcodeproject.dev` (via Cloudflare tunnel)
- **Local:** `*.lab` (direct connection to Traefik)

> **Note:** Using `.lab` instead of `.local` because `.local` is reserved for mDNS/Bonjour and can cause conflicts.

## Goals

1. Allow fast local access without internet roundtrip
2. Maintain existing public access functionality
3. Use same Traefik infrastructure for both routes
4. Minimize configuration changes
5. Provide clear user documentation

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      CLIENT DEVICE                               │
│  Browser requests: gitlab.lab or gitlab.weekendcodeproject.dev   │
└──────────────────────────────────────────────────────────────────┘
                               ↓
         ┌─────────────────────┴──────────────────────┐
         ↓                                             ↓
┌─────────────────────┐                   ┌───────────────────────┐
│  gitlab.lab         │                   │  gitlab.weekend...dev │
│  Router DNS or      │                   │  DNS → Cloudflare     │
│  /etc/hosts lookup  │                   │  → Tunnel             │
│  → 192.168.2.50     │                   │                       │
└─────────────────────┘                   └───────────────────────┘
         ↓                                             ↓
         └─────────────────────┬──────────────────────┘
                               ↓
              ┌────────────────────────────────┐
              │  TRAEFIK (192.168.2.50:80/443) │
              │  Reads HTTP Host header        │
              │  Matches router rules          │
              └────────────────────────────────┘
                               ↓
              ┌────────────────────────────────┐
              │  Traefik Router for GitLab:    │
              │  Host(`gitlab.weekendcode...`) │
              │       || Host(`gitlab.lab`)    │
              └────────────────────────────────┘
                               ↓
                      ┌────────────────┐
                      │ GitLab Container│
                      │  (port 80)      │
                      └────────────────┘
```

**Key Concept:** Traefik routes based on HTTP `Host` header, not IP address. Both domains can route to the same container because they send different Host headers.

---

## Implementation Phases

### Phase 1: Identify All Services with Traefik Labels

**Services requiring updates:**

| Category | Service | Current Domain Pattern | Local Domain |
|----------|---------|------------------------|--------------|
| **Development** | gitlab | `gitlab.${BASE_DOMAIN}` | gitlab.lab |
| | gitea | `gitea.${BASE_DOMAIN}` | gitea.lab |
| | coder | `coder.${BASE_DOMAIN}` | coder.lab |
| | registry-cache | `registry.${BASE_DOMAIN}` | registry.lab |
| **Productivity** | postiz | `postiz.${BASE_DOMAIN}` | postiz.lab |
| | nocodb | `nocodb-${COMPUTER_NAME}.${BASE_DOMAIN}` | nocodb.lab |
| | paperless-ngx | `paperless.${BASE_DOMAIN}` | paperless.lab |
| | n8n | `n8n.${BASE_DOMAIN}` | n8n.lab |
| | focalboard | `focalboard.${BASE_DOMAIN}` | focalboard.lab |
| | trilium | `trilium.${BASE_DOMAIN}` | trilium.lab |
| | vikunja | `vikunja.${BASE_DOMAIN}` | vikunja.lab |
| | docmost | `docmost.${BASE_DOMAIN}` | docmost.lab |
| | activepieces | `activepieces.${BASE_DOMAIN}` | activepieces.lab |
| | bytestash | `bytestash.${BASE_DOMAIN}` | bytestash.lab |
| | excalidraw | `excalidraw.${BASE_DOMAIN}` | excalidraw.lab |
| | it-tools | `it-tools.${BASE_DOMAIN}` | it-tools.lab |
| **Personal** | mealie | `mealie.${BASE_DOMAIN}` | mealie.lab |
| | firefly | `firefly.${BASE_DOMAIN}` | firefly.lab |
| | wger | `wger.${BASE_DOMAIN}` | wger.lab |
| **Monitoring** | dozzle | `dozzle.${BASE_DOMAIN}` | dozzle.lab |
| | wud | `wud.${BASE_DOMAIN}` | wud.lab |
| | uptime-kuma | `uptime.${BASE_DOMAIN}` | uptime.lab |
| | netdata | `netdata.${BASE_DOMAIN}` | netdata.lab |
| | portainer | `portainer.${BASE_DOMAIN}` | portainer.lab |
| | duplicati | `duplicati.${BASE_DOMAIN}` | duplicati.lab |
| | netbox | `netbox.${BASE_DOMAIN}` | netbox.lab |
| **Media** | immich-server | `immich.${BASE_DOMAIN}` | immich.lab |
| | kavita | `kavita.${BASE_DOMAIN}` | kavita.lab |
| | navidrome | `navidrome.${BASE_DOMAIN}` | navidrome.lab |
| **AI** | open-webui | `chat.${BASE_DOMAIN}` | chat.lab |
| | librechat | `librechat.${BASE_DOMAIN}` | librechat.lab |
| | anythingllm | `anythingllm.${BASE_DOMAIN}` | anythingllm.lab |
| | searxng | `searxng.${BASE_DOMAIN}` | searxng.lab |
| | localai | `localai.${BASE_DOMAIN}` | localai.lab |
| **Core** | homer | `home.${BASE_DOMAIN}` | home.lab |
| | homer-public | `${BASE_DOMAIN}` | weekendstack.lab |
| | vaultwarden | `vault.${BASE_DOMAIN}` | vault.lab |
| **Networking** | traefik | `traefik.${BASE_DOMAIN}` | traefik.lab |
| | pihole | `pihole.${BASE_DOMAIN}` | pihole.lab |
| **Automation** | homeassistant | `homeassistant.${BASE_DOMAIN}` | homeassistant.lab |
| | nodered | `nodered.${BASE_DOMAIN}` | nodered.lab |

**Estimated services:** ~40 services requiring label updates

---

### Phase 2: Update Docker Compose Files

#### Pattern to Apply

**Before:**
```yaml
labels:
  - traefik.http.routers.SERVICE.rule=Host(`SERVICE.${BASE_DOMAIN}`)
```

**After:**
```yaml
labels:
  - traefik.http.routers.SERVICE.rule=Host(`SERVICE.${BASE_DOMAIN}`) || Host(`SERVICE.lab`)
```

#### Files to Modify

1. **docker-compose.dev.yml**
   - gitlab
   - gitea
   - coder
   - registry-cache

2. **docker-compose.productivity.yml**
   - postiz
   - nocodb (special handling for COMPUTER_NAME variable)
   - paperless-ngx
   - n8n
   - focalboard
   - trilium
   - vikunja
   - docmost
   - activepieces
   - bytestash
   - excalidraw
   - it-tools

3. **docker-compose.personal.yml**
   - mealie
   - firefly
   - wger

4. **docker-compose.monitoring.yml**
   - dozzle
   - wud
   - uptime-kuma
   - netdata
   - portainer
   - duplicati
   - netbox

5. **docker-compose.media.yml**
   - immich-server
   - kavita
   - navidrome

6. **docker-compose.ai.yml**
   - open-webui
   - librechat
   - anythingllm
   - searxng
   - localai

7. **docker-compose.core.yml**
   - homer
   - homer-public
   - vaultwarden

8. **docker-compose.networking.yml**
   - traefik (dashboard)
   - pihole

9. **docker-compose.automation.yml**
   - homeassistant
   - nodered

#### Special Cases

**NocoDB with COMPUTER_NAME variable:**
```yaml
# Before:
- traefik.http.routers.nocodb.rule=Host(`${NOCODB_DOMAIN:-nocodb-${COMPUTER_NAME}.${BASE_DOMAIN}}`)

# After:
- traefik.http.routers.nocodb.rule=Host(`${NOCODB_DOMAIN:-nocodb-${COMPUTER_NAME}.${BASE_DOMAIN}}`) || Host(`nocodb.lab`)
```

**Homer-public (root domain):**
```yaml
# Before:
- traefik.http.routers.homer-public.rule=Host(`${BASE_DOMAIN}`)

# After:
- traefik.http.routers.homer-public.rule=Host(`${BASE_DOMAIN}`) || Host(`weekendstack.lab`)
```

**Coder Workspaces (if applicable):**
- Coder workspaces use Terraform templates, not Docker Compose
- May require separate Terraform template updates
- Pattern: `Host(\`workspace-name.${BASE_DOMAIN}\`) || Host(\`workspace-name.lab\`)`

---

### Phase 3: DNS Configuration

**Choose ONE of the following:**

#### Option A: Router-Level Wildcard DNS (Recommended)

Configure wildcard DNS on your router for network-wide automatic resolution.

**UniFi Networks:**
1. SSH to UniFi Gateway/Controller
2. Add wildcard DNS:
   ```bash
   configure
   set service dns forwarding options 'address=/lab/192.168.2.50'
   commit
   save
   exit
   ```
3. Test: `nslookup anything.lab` should return `192.168.2.50`

**Other Routers:**
- **pfSense/OPNsense:** Services → DNS Resolver → Host Overrides
- **DD-WRT:** Services → DNSMasq → `address=/lab/192.168.2.50`
- **OpenWrt:** Network → DHCP and DNS → Hostnames
- **ASUS Merlin:** LAN → DNSFilter → Custom dnsmasq config
- **Mikrotik:** IP → DNS → Static

**Advantages:**
- Network-wide automatic configuration
- True wildcard - ANY `.lab` subdomain works
- No client-side configuration needed
- Identical behavior to Cloudflare tunnel

**Disadvantages:**
- Requires router admin access
- Some routers don't support wildcard DNS
- May not persist across firmware updates (varies by router)

#### Option B: Pi-hole Wildcard DNS

If you have Pi-hole in your stack:

1. Add wildcard rule:
   ```bash
   docker exec -it pihole bash
   echo "address=/lab/192.168.2.50" >> /etc/dnsmasq.d/02-custom.conf
   pihole restartdns
   ```

2. Configure devices to use Pi-hole as DNS (192.168.2.50)

**Advantages:**
- Same as router method
- More persistent than some router configs
- Can manage alongside other Pi-hole features

**Disadvantages:**
- Requires Pi-hole running
- Requires DNS configuration on devices or router DHCP

#### Option C: Manual Hosts File (Fallback)

If router/Pi-hole options aren't available, add entries per device.

See `docs/local-access-setup.md` for detailed instructions.

**Advantages:**
- Works on any device
- No network infrastructure changes

**Disadvantages:**
- Must configure each device individually
- Must add entry for each new service manually
- No wildcard support

---

### Phase 4: Validation & Testing

#### Pre-Deployment Validation

1. **Syntax Check:**
   ```bash
   docker compose config
   ```
   Should show no errors and properly expanded labels

2. **Review Generated Config:**
   ```bash
   docker compose config | grep "traefik.http.routers" | grep "rule"
   ```
   Verify all rules include `|| Host(` pattern

#### Deployment

1. **Recreate Services:**
   ```bash
   docker compose up -d --force-recreate
   ```

2. **Verify Traefik Config:**
   ```bash
   docker logs traefik 2>&1 | grep -i "router"
   ```
   Check for any routing errors

3. **Check Traefik Dashboard:**
   - Access: http://192.168.2.50:8080
   - Navigate to: HTTP → Routers
   - Verify each service shows dual Host rule

#### Testing Plan

1. **Without DNS configuration (baseline):**
   - Access service via: `https://SERVICE.weekendcodeproject.dev`
   - Verify: Should work as before

2. **Configure DNS (router or Pi-hole):**
   - Add wildcard DNS rule: `*.lab → 192.168.2.50`
   - Restart DNS service

3. **Test wildcard resolution:**
   ```bash
   nslookup gitlab.lab
   nslookup randomname.lab
   # Both should return: 192.168.2.50
   ```

4. **Test local access:**
   - Access: `https://gitlab.lab`
   - Verify: Reaches GitLab (may show SSL warning - this is expected)
   - Verify: Can log in and use normally

5. **Test both simultaneously:**
   - In one browser tab: `https://gitlab.lab`
   - In another tab: `https://gitlab.weekendcodeproject.dev`
   - Verify: Both reach same GitLab instance
   - Verify: Login session shared between both

6. **Test from multiple devices:**
   - Phone/tablet on WiFi
   - Laptop on WiFi
   - Desktop on Ethernet
   - All should resolve `.lab` domains automatically (if using router DNS)

7. **Test NEW service:**
   - Add new service with dual-domain label
   - Without any DNS changes, `newservice.lab` should already work (wildcard!)

8. **Network isolation test:**
   - Disconnect test device from internet (keep WiFi/LAN connected)
   - Access: `https://SERVICE.lab`
   - Verify: Still works (proving local routing)
   - Access: `https://SERVICE.weekendcodeproject.dev`
   - Verify: Fails (no internet, expected)

---

### Phase 5: User Documentation

**Documents to Create/Update:**

1. **✅ docs/local-access-setup.md** (Created)
   - User-facing guide for DNS configuration
   - UniFi-specific instructions
   - Alternative router instructions
   - Troubleshooting section

2. **docs/traefik-setup.md** (Update)
   - Add section on dual-domain routing
   - Explain how the OR logic works
   - Document label pattern

3. **docs/services-guide.md** (Update)
   - Add `.lab` domain URLs to service list
   - Update access instructions

4. **README.md** (Update)
   - Add quick reference to local access
   - Link to full setup guide

5. **docs/network-architecture.md** (Update if exists)
   - Diagram showing dual-domain flow with router DNS
   - Explain routing decision logic

---

## Rollback Plan

If issues arise, rollback is straightforward:

1. **Revert Docker Compose changes:**
   ```bash
   git checkout HEAD -- docker-compose.*.yml
   ```

2. **Recreate services:**
   ```bash
   docker compose up -d --force-recreate
   ```

3. **Verify public access restored:**
   - Test: `https://SERVICE.weekendcodeproject.dev`

**Time to rollback:** ~5 minutes

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Syntax error in labels | Medium | High | Pre-deployment validation with `docker compose config` |
| Traefik routing conflict | Low | Medium | Test thoroughly before full rollout |
| SSL warnings confuse users | High | Low | Clear documentation in user guide |
| Performance impact | Very Low | Low | Traefik handles OR rules efficiently |
| Public access breaks | Very Low | High | Test public domain before deploying to all services |
| Router DNS misconfiguration | Medium | Medium | Provide exact commands, test with simple ping/nslookup |
| DNS not persistent | Low | Medium | Document per-router persistence requirements |

---

## Timeline Estimate

| Phase | Time | Notes |
|-------|------|-------|
| Label Updates | 1-2 hours | ~40 services, can be batched |
| DNS Configuration | 5-15 minutes | Router SSH + single command |
| Testing | 30 minutes | Test representative services + wildcard |
| Documentation | 1 hour | Updates to existing docs |
| User Support | Ongoing | Answer questions as needed |
| **Total** | **2-3 hours** | Much faster with router DNS vs hosts files |

---

## Success Criteria

- [ ] All services accessible via `*.weekendcodeproject.dev` (unchanged)
- [ ] All services accessible via `*.lab` (new)
- [ ] Wildcard DNS working: `randomname.lab` resolves to `192.168.2.50`
- [ ] No errors in `docker compose config`
- [ ] No errors in Traefik logs
- [ ] Traefik dashboard shows dual Host rules for all services
- [ ] Test device can access services both ways
- [ ] Multiple devices can access via `.lab` without individual configuration
- [ ] User documentation complete and clear
- [ ] No performance degradation observed

---

## Post-Implementation

### Monitoring

1. **Check Traefik logs** for routing errors:
   ```bash
   docker logs -f traefik
   ```

2. **Verify DNS resolution across network:**
   ```bash
   # From multiple devices
   nslookup gitlab.lab
   nslookup newservice.lab
   ```

3. **Monitor access patterns** (if using Traefik access logs):
   - Track usage of `.lab` vs `.weekendcodeproject.dev`
   - Identify popular local-access services

4. **User feedback:**
   - Create issue template for access problems
   - Track common configuration mistakes

### Optimization Opportunities

1. **Persistent Router Configuration:**
   - For routers that don't persist dnsmasq configs
   - Create startup script or backup/restore mechanism
   - Document per-router persistence strategies

2. **Local Certificate Authority:**
   - Generate CA for `*.lab` domains
   - Eliminate SSL warnings
   - Distribute CA cert to devices via MDM or manual install

3. **Homer Dashboard Update:**
   - Add toggle to switch between local/public URLs
   - Auto-detect network and suggest appropriate domain
   - Show `.lab` links when on local network

4. **Router-Specific Guides:**
   - Create detailed guides for popular routers
   - Screenshots for GUI-based configuration
   - Backup/restore instructions

---

## Alternative Approaches Considered

### Option A: Separate Traefik Entrypoints
- Create separate entrypoint for local access
- **Pros:** Clean separation
- **Cons:** More complex, requires different ports
- **Rejected:** Over-engineered for this use case

### Option B: DNS-Only Solution
- Use Pi-hole or router DNS to override `*.weekendcodeproject.dev`
- **Pros:** No label changes needed
- **Cons:** Breaks external access when on local network, SSL cert issues
- **Rejected:** Breaks public domain when on local network

### Option C: Wildcard DNS with `.local` TLD
- Use `*.local` with router DNS
- **Pros:** Familiar TLD
- **Cons:** `.local` is reserved for mDNS/Bonjour, causes conflicts
- **Rejected:** Technical conflict with mDNS standard

### Option D: Tailscale MagicDNS
- Use Tailscale hostnames like `gitlab.tailnet.ts.net`
- **Pros:** Works anywhere, built-in encryption
- **Cons:** Requires Tailscale on all devices, different domain
- **Status:** Complementary solution, not replacement

### Option D: Wildcard DNS + Hosts File for Root
- Point `*.weekendcodeproject.dev` to 192.168.2.50 locally
- **Pros:** Matches public domain exactly
- **Cons:** SSL certificate complexity, less obvious local routing
- **Rejected:** SSL cert management too complex

**Selected Approach:** Dual-domain with `*.lab` suffix + Router Wildcard DNS
- **Why:** Simple, explicit, minimal per-device changes, clear local vs remote distinction, true wildcard like Cloudflare tunnel
- **Advantages over hosts file:** Network-wide automatic configuration, works for new services automatically, no client configuration needed

---

## Dependencies

### Required
- Traefik v3.0+ (already deployed)
- Docker Compose (already deployed)
- Valid `BASE_DOMAIN` environment variable
- Cloudflare tunnel (already configured)

### Optional
- Pi-hole (for alternative to router DNS)
- Local CA (for SSL without warnings)
- Tailscale (for remote access without public domain)
- Router with wildcard DNS support (UniFi, pfSense, DD-WRT, OpenWrt, etc.)

---

## Maintenance Notes

### When Adding New Services

Always include dual-domain pattern in Traefik labels:
```yaml
labels:
  - traefik.http.routers.NEWSERVICE.rule=Host(`NEWSERVICE.${BASE_DOMAIN}`) || Host(`NEWSERVICE.lab`)
```

**No DNS changes needed!** Wildcard DNS automatically resolves `NEWSERVICE.lab` to the server.

### When Changing Domains

If `BASE_DOMAIN` changes:
1. Labels automatically update (uses `${BASE_DOMAIN}`)
2. Update documentation examples
3. `.lab` domains unaffected (don't reference BASE_DOMAIN)
4. Wildcard DNS unaffected

### When Changing Server IP

If server IP changes from 192.168.2.50:
1. Update router wildcard DNS rule: `address=/lab/<NEW_IP>`
2. Update documentation examples
3. Changes propagate automatically to all devices (network-wide)
4. Consider using DHCP reservation to prevent IP changes

---

## Conclusion

This implementation plan provides:
- ✅ Clear technical architecture
- ✅ Step-by-step implementation phases
- ✅ Multiple DNS configuration options (router/Pi-hole/manual)
- ✅ Comprehensive testing strategy
- ✅ User documentation
- ✅ Risk mitigation
- ✅ Rollback procedure
- ✅ Success criteria

The dual-domain approach with router-level wildcard DNS is simple, maintainable, provides network-wide automatic configuration, and mirrors the Cloudflare tunnel behavior for local access.

**Recommendation:** Proceed with implementation using router-level wildcard DNS for best user experience.
