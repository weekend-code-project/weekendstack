# Coder Template System: v1 → v2 Migration Plan

**Created:** 2026-02-19  
**Branch:** feature/smart-image-pull-optimization  
**Status:** Planning — v2 partially built, v1 is live and working

---

## Current State

### What's Working (v1)
Five templates deployed and live in Coder via the v1 system:
- `docker-template` — minimal Docker workspace
- `modular-test` — test harness for module development  
- `node-template` — Node.js dev environment
- `vite-template` — Vite + Node frontend dev environment
- `wordpress-template` — WordPress dev environment

### v2 Progress (partial)
The v2 system was started on 2026-01-11 and is located at `config/coder/v2/`.
Two modules exist, one template works:
- ✅ `modules/feature/code-server` — code-server web IDE
- ✅ `modules/feature/traefik-routing` — Traefik label injection
- ⏳ `modules/platform/` — empty (coder-agent, docker-workspace needed)
- ⏳ `modules/step/` — empty (startup script steps needed)
- ✅ `templates/base/` — minimal working template (pushed as `new-modular-template` v4)
- ✅ `scripts/push-template.sh` — new manifest-driven push script

---

## What Calls v1 Templates (Full Callsite Map)

### Deployment Callsites
| File | Line(s) | Reference | Action Needed |
|------|---------|-----------|---------------|
| `config/coder/scripts/deploy-all-templates.sh` | 17 | `TEMPLATES_DIR="$WORKSPACE_ROOT/config/coder/templates"` | Change to `v2/templates` |
| `config/coder/scripts/deploy-all-templates.sh` | 20 | `PUSH_SCRIPT="$SCRIPT_DIR/push-template-local.sh"` | Change to `v2/scripts/push-template.sh` |
| `tools/coder/scripts/deploy-all-templates.sh` | 17, 20 | Same as above (mirror copy) | Same changes |
| `setup.sh` | 281 | `config/coder/scripts/deploy-all-templates.sh` | No change — script path stays, internals change |
| `Makefile` | 99, 107, 114 | `config/coder/scripts/deploy-all-templates.sh` | No change — script path stays |

### Documentation References (non-breaking)
| File | Reference |
|------|-----------|
| `tools/setup/lib/summary.sh:122` | Text mention of `config/coder/templates/` — update to remove path |
| `config/coder/template-modularization-plan.md` | Old planning doc — archive or delete |
| `config/coder/docs/modular-template-refactor-roadmap.md` | Living doc — keep, update status |

### Scripts That Will Be Retired
| Script | Purpose | Retirement Condition |
|--------|---------|---------------------|
| `config/coder/scripts/push-template-local.sh` | v1 push — copies modules from template-modules/ | After all v2 templates verified |
| `tools/coder/scripts/push-template-local.sh` | Mirror of above | Same |
| `config/coder/template-modules/` | Shared modules/params for v1 | After all v2 templates verified |

---

## Migration Phases

### Phase 1: Complete the v2 Module Library
**Goal:** Have all modules needed to replicate v1 template capabilities  
**Scope:** `config/coder/v2/modules/`

#### 1.1 Platform Modules (required by every template)
- [ ] `modules/platform/coder-agent/` — Coder agent resource + workspace data sources
- [ ] `modules/platform/docker-workspace/` — Docker container, image, volume resources

#### 1.2 Feature Modules
- [x] `modules/feature/code-server/` — web IDE ✅
- [x] `modules/feature/traefik-routing/` — routing labels ✅
- [ ] `modules/feature/ssh/` — SSH access (port forward via Coder)
- [ ] `modules/feature/git-integration/` — gitconfig + SSH key injection
- [ ] `modules/feature/node-tooling/` — nvm, Node.js version management
- [ ] `modules/feature/wordpress/` — WordPress + MySQL sidecar container

#### 1.3 Step Modules (startup script parts)
- [ ] `modules/step/init-shell/` — baseline shell config (aliases, PATH)
- [ ] `modules/step/setup-workspace/` — clone repo, directory scaffold
- [ ] `modules/step/node-install/` — nvm install + node version pin
- [ ] `modules/step/preview-server/` — start and register preview link

**Acceptance:** `push-template.sh --dry-run base` compiles a startup script from at least 3 step modules cleanly.

---

### Phase 2: Port the Four Production Templates to v2
**Goal:** One v2 template for each v1 template (drop `modular-test` — replaced by `base`)

Templates to create in `config/coder/v2/templates/`:

#### 2.1 `docker` (replaces `docker-template`)
- Modules: platform/coder-agent, platform/docker-workspace, feature/code-server
- No SSH, no Git, no Node
- Manifest: minimal, 3 modules + 2 step modules

#### 2.2 `node` (replaces `node-template`)
- Modules: docker, code-server, ssh, git-integration, node-tooling, traefik-routing
- Steps: init-shell, setup-workspace, node-install, preview-server
- Paramters: node version, git repo, preview port

#### 2.3 `vite` (replaces `vite-template`)
- Same as `node` + vite-specific startup command default
- Could be same template as `node` with a different default startup_command parameter

#### 2.4 `wordpress` (replaces `wordpress-template`)
- Modules: docker, code-server, ssh, git-integration, wordpress, traefik-routing
- Steps: init-shell, setup-wordpress, preview-server
- Requires MySQL sidecar defined in platform/docker-workspace variant

**Acceptance:** Each template can be pushed with `push-template.sh <name>` and creates a working Coder workspace.

---

### Phase 3: Wire v2 into the Deployment Pipeline
**Goal:** `make deploy-coder-templates` and `./setup.sh` use v2, not v1

#### 3.1 Update `deploy-all-templates.sh` (both copies)
Change two lines in both `config/coder/scripts/deploy-all-templates.sh` and `tools/coder/scripts/deploy-all-templates.sh`:

```bash
# Before
TEMPLATES_DIR="$WORKSPACE_ROOT/config/coder/templates"
PUSH_SCRIPT="$SCRIPT_DIR/push-template-local.sh"

# After
TEMPLATES_DIR="$WORKSPACE_ROOT/config/coder/v2/templates"
PUSH_SCRIPT="$WORKSPACE_ROOT/config/coder/v2/scripts/push-template.sh"
```

The template discovery loop in `deploy-all-templates.sh` iterates `$TEMPLATES_DIR/*/` — this will work unchanged for v2 templates as long as template directory names don't start with `_`.

#### 3.2 Verify `setup.sh` integration
`setup.sh:281` calls `config/coder/scripts/deploy-all-templates.sh` — no change needed once step 3.1 is done.

#### 3.3 Update Makefile `redeploy-coder-templates`
The `force` positional arg in `deploy-all-templates.sh` is already handled. No change needed.

#### 3.4 Update `tools/setup/lib/summary.sh`
Remove the hardcoded path reference on line 122. Replace with generic language.

**Acceptance:** `make deploy-coder-templates` deploys all 4 v2 templates to a fresh Coder instance.

---

### Phase 4: Cutover and Cleanup
**Goal:** Remove v1 code. Done only after Phase 3 is verified in a clean install.

#### 4.1 Archive v1 templates (don't delete immediately)
```bash
git mv config/coder/templates config/coder/templates-v1-archive
```
This keeps the git history accessible while making it clear they're retired.

#### 4.2 Remove v1 scripts
```bash
git rm config/coder/scripts/push-template-local.sh
git rm tools/coder/scripts/push-template-local.sh
```

#### 4.3 Remove template-modules (v1 shared modules)
```bash
git rm -r config/coder/template-modules
```

#### 4.4 Remove archive after one release
Once v2 is confirmed stable across two clean installs, remove:
```bash
git rm -r config/coder/templates-v1-archive
```

---

## Key Differences: v1 vs v2

| Concern | v1 | v2 |
|---------|----|----|
| Module discovery | `modules.txt` list → `push-template-local.sh` copies from `template-modules/` | `manifest.json` → `push-template.sh` compiles from `v2/modules/` |
| Startup script | Each module injects into `agent-params.tf` at push time | `push-template.sh` compiles one `startup.sh` from `step/*.part.sh` files |
| Terraform structure | Flat files scattered in template dir + copied module dirs | Clean Terraform modules with defined outputs |
| Host path deps | Had some (`/opt/stacks/...`) | None — labels + named volumes only |
| Version naming | Auto-increments (v1, v2, v3...) via `push-template-local.sh` | Same behavior in `push-template.sh` |
| Deploy orchestrator | `deploy-all-templates.sh` → `push-template-local.sh` | `deploy-all-templates.sh` → `push-template.sh` (same outer script) |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| v2 templates not yet complete — clean installs fail | Keep v1 as fallback until Phase 3 is done and verified |
| `push-template.sh` has different arg signature than `push-template-local.sh` | Audit `deploy-all-templates.sh` call sites before Phase 3; adapt args |
| `vite` and `node` may be so similar one could replace both | Test first; if identical, use one template with different parameter defaults |
| WordPress sidecar (MySQL) complicates platform/docker-workspace | May need a separate `platform/docker-wordpress/` variant |
| Coder template version history reset on rename | Use same template names (`node`, not `node-template`) so Coder sees them as new templates, not updates |

---

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-01-11 | Start v2 in `/config/coder/v2/` instead of modifying v1 | Clean slate avoids breaking working templates during migration |
| 2026-01-11 | Build-time script compilation (not runtime sourcing) | Eliminates startup order bugs present in v1 |
| 2026-01-11 | Traefik BasicAuth via labels (not host bind mount) | Removes host path dependency |
| 2026-02-19 | Defer cutover until all 4 templates are verified working | Don't break clean install while migrating |

---

## Next Session Checklist

Start here next time:
1. `cd config/coder/v2`
2. Run `./scripts/push-template.sh --dry-run base` to verify v2 push script still works
3. Begin Phase 1.1: create `modules/platform/coder-agent/main.tf`
4. Create `modules/platform/docker-workspace/main.tf`
5. Create first step module: `modules/step/init-shell/`
6. Update `templates/base/` to use the new platform modules via manifset
7. Push and create a test workspace

**The goal of the first coding session is:** a `base` template that works end-to-end using only v2 modules (no v1 module copies), with at least one step module in the compiled startup script.
