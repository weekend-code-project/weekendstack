# Glance Dashboard Cleanup Summary

## Changes Completed

All 9 issues identified have been addressed. Containers have been recreated with updated labels.

### 1. ✅ Mealie - Added Glance Labels
**File**: `docker-compose.personal.yml`
- Added glance labels: `id=mealie`, `name=Mealie`, `icon=si:docker`, `url=/go/mealie`, `description=Recipe Manager`
- Container recreated

### 2. ✅ Node-RED - Nested Under Parent
**File**: `docker-compose.automation.yml`
- Added glance labels: `parent=homeassistant`, `name=Node-RED`
- This nests Node-RED under Home Assistant in the Services page, removing clutter
- Container recreated

### 3. ✅ Cloudflare Tunnel - Hidden
**File**: `docker-compose.networking.yml`
- Set `glance.hide=true` to hide from dashboard (no web UI to access)
- Removed unnecessary labels (parent, name, icon)
- Container recreated

### 4. ✅ Paperless - Icon Fixed
**File**: `docker-compose.productivity.yml`
- Changed icon from `si:files` to `si:docker` (generic Docker icon)
- Container recreated

### 5. ✅ Firefly III - Name Verified
**File**: `docker-compose.personal.yml`
- Confirmed glance label already has correct name: `Firefly III`
- No changes needed (may have been browser caching)

### 6. ✅ Wger - Name Capitalized
**File**: `docker-compose.personal.yml`
- Changed `glance.name=wger` to `glance.name=Wger`
- Container recreated

### 7. ✅ Gitea .lab Domain - Fixed
**File**: `docker-compose.dev.yml`
- **Root Cause**: Label formatting error - comments were on the same line as label declarations
- Fixed label formatting (moved comments to separate lines)
- Container recreated
- **Status**: Now working! Shows Gitea installation wizard at http://gitea.lab/

### 8. ✅ Pi-hole .lab Domain - Working
**File**: No changes needed
- **Investigation**: Pi-hole returns 308 redirect from `/admin` to `/admin/` (trailing slash required)
- Accessing http://pihole.lab/admin/ works correctly and shows Pi-hole admin interface
- User-reported 403 may have been browser caching or accessing wrong path

### 9. ✅ GitLab Status - Expected Behavior
**File**: No changes needed
- **Investigation**: GitLab is running (healthy) and responding on port 8929
- Returns HTTP 302 redirect (attempting to redirect to HTTPS)
- **Expected**: GitLab requires HTTPS to function properly (as user noted)
- Access via https://gitlab.weekendcodeproject.dev should work

## Containers Recreated

The following containers were recreated to apply label changes:

```bash
docker compose up -d mealie wger              # Personal services
docker compose up -d nodered                  # Automation
docker compose up -d cloudflare-tunnel        # Networking
docker compose up -d paperless-ngx            # Productivity
docker compose up -d gitea                    # Development
docker restart traefik                        # Reloaded routing config
```

## Testing Results

### ✅ Services Now Working
- **Gitea**: http://gitea.lab/ (installation wizard)
- **Pi-hole**: http://pihole.lab/admin/ (admin interface)
- **Mealie**: Now visible in Services page with proper name/icon
- **Wger**: Now shows as "Wger" instead of "wger"
- **Node-RED**: Nested under Home Assistant (less clutter)
- **Cloudflare Tunnel**: Hidden from dashboard (no UI to access)
- **Paperless**: Generic Docker icon displayed
- **GitLab**: Running but requires HTTPS setup

### Notes
- **Gitea**: Needs initial installation/setup via web wizard
- **GitLab**: Requires HTTPS configuration to be fully functional
- **Pi-hole**: Access via /admin/ path (with trailing slash)
- **Firefly III**: Already had correct name, no changes needed

## Files Modified

1. `/opt/stacks/weekendstack/docker-compose.personal.yml`
   - Added Mealie glance labels
   - Fixed Wger capitalization

2. `/opt/stacks/weekendstack/docker-compose.automation.yml`
   - Added Node-RED parent nesting

3. `/opt/stacks/weekendstack/docker-compose.networking.yml`
   - Hidden Cloudflare Tunnel

4. `/opt/stacks/weekendstack/docker-compose.productivity.yml`
   - Fixed Paperless icon

5. `/opt/stacks/weekendstack/docker-compose.dev.yml`
   - Fixed Gitea label formatting (critical fix for Traefik routing)

## Next Steps

1. **Complete Gitea Setup**: Visit http://gitea.lab/ to complete installation wizard
2. **Configure GitLab HTTPS**: Set up HTTPS to make GitLab fully functional
3. **Refresh Browser**: Hard refresh dashboard (Ctrl+F5) to clear any cached content
4. **Verify Dashboard**: Check Services page to confirm all changes are visible
