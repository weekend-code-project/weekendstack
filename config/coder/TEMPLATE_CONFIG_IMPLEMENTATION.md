# Template Config Implementation Progress

**Goal:** Convert all templates to use config-based `modules.txt` system

**Branch:** `cleanup/template-system-standardization`

---

## Implementation Checklist

### ✅ System Setup
- [x] Create `modules.txt` format specification
- [x] Enhance `push-template-versioned.sh` to process configs
- [x] Create `set-debug-phase.sh` helper script
- [x] Test with debug-template Phase 0 & 1

### 🔄 test-template (Docker-style baseline)
- [ ] Create `test-template/modules.txt`
- [ ] Update `test-template/agent-params.tf` with required locals
- [ ] Test Phase 1: core modules only (code-server, agent)
- [ ] Test Phase 2: + metadata
- [ ] Test Phase 3: + ssh (CRITICAL - expect flickering)
- [ ] Test Phase 4: + setup-server (if ssh clean)
- [ ] Document flickering findings
- [ ] Copy working config to docker-template

### ⏸️ docker-template
- [ ] Copy validated modules.txt from test-template
- [ ] Test push
- [ ] Verify workspace creation
- [ ] Mark as production-ready

### ⏸️ node-template
- [ ] Create modules.txt with all 14 modules
- [ ] Test incremental addition
- [ ] Verify all features work
- [ ] Check for flickering with full config

### ⏸️ vite-template
- [ ] Create modules.txt (similar to node)
- [ ] Test vite-specific server config
- [ ] Verify HMR and preview links
- [ ] Check for flickering

### ⏸️ wordpress-template
- [ ] Analyze module usage
- [ ] Create modules.txt
- [ ] Test WordPress-specific features

---

## Test Progress Log

### test-template Implementation

**Phase 1: Core Modules**
- Date: 2026-01-04
- Modules: code-server, agent
- Status: 
- Flickering: 
- Notes:

**Phase 2: + Metadata**
- Date:
- Modules: + metadata
- Status:
- Flickering:
- Notes:

**Phase 3: + SSH (HIGH RISK)**
- Date:
- Modules: + ssh
- Status:
- Flickering:
- Notes:

**Phase 4: + Setup Server**
- Date:
- Modules: + setup-server
- Status:
- Flickering:
- Notes:

---

## Module Reference

**Available Modules:**
- `code-server` - VS Code in browser (no params)
- `coder-agent` - Agent config (params)
- `init-shell` - Shell setup (no params)
- `metadata` - Monitoring (params)
- `docker` - Docker-in-Docker (params)
- `ssh` - SSH server (params) ⚠️ HIGH RISK
- `setup-server` - Dev server (params) ⚠️ HIGH RISK
- `git-identity` - Git config (params)
- `git-integration` - Git clone (params)
- `github-cli` - GitHub CLI (params)
- `gitea-cli` - Gitea CLI (params)
- `node-tooling` - Node.js (params)
- `node-modules-persistence` - node_modules cache (params)
- `preview-link` - Preview buttons (params)
- `traefik` - Routing (params)

**Format:**
```
module-name              # No params
module-name:params       # With params (shared)
module-name:params:override  # With params (template-local)
```

---

## Findings & Decisions

### Flickering Culprit
- **Module:** TBD
- **Pattern:** TBD
- **Fix:** TBD

### Template Simplifications
- Document what can be removed from main.tf
- Document what can be removed from template directories
- List which param files should be shared vs overridden
