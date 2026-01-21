# Modular Template System Simplification Plan

**Created:** January 8, 2026  
**Status:** Implementation Ready  
**Goal:** Eliminate debugging friction while preserving modularity and preparing for GitHub distribution

---

## Executive Summary

The current modular Coder template system requires pushing to GitHub before testing module changes, making debugging slow and painful. This plan implements a **local-first development workflow** that copies modules directly during template push, eliminating the GitHub fetch dependency during development. The architecture is designed so the final production deployment can seamlessly switch back to GitHub-sourced modules.

### Current Pain Points

1. **Debugging requires Git push** — Must commit and push module changes to GitHub before testing in Coder templates
2. **Slow iteration cycle** — Change → commit → push → wait → test → repeat
3. **Module execution issues** — Some modules not running/loading correctly, hard to debug with current workflow
4. **GitHub rate limits** — Multiple git module fetches can hit API limits
5. **Network dependency** — Can't work offline or in disconnected environments

### Solution Overview

**Development Mode (Immediate):** Copy all module code locally to temp folder during push  
**Production Mode (Future):** Replace local copies with GitHub module sources  
**Bridge:** Environment-specific values (BASE_DOMAIN, HOST_IP) always injected at push time regardless of mode

---

## Architecture Principles

### 1. Separation of Concerns

**Static Reusable Logic (GitHub-friendly)**
- Module `main.tf` files contain pure Terraform logic
- No hardcoded paths, IPs, or environment-specific values
- Use variables with sensible defaults (`variable "base_domain" { default = "localhost" }`)
- Outputs follow naming conventions for auto-detection

**Environment-Specific Configuration (Injected at push)**
- BASE_DOMAIN, HOST_IP, SSH_KEY_DIR, TRAEFIK_AUTH_DIR
- Injected via substitution in temp files before push
- Never committed to Git
- Loaded from workspace `.env` file

### 2. Module Interface Contract

All modules must follow these rules to support both local and GitHub sourcing:

```hcl
# ✅ GOOD: Uses variable with default
variable "base_domain" {
  description = "Base domain for routing"
  type        = string
  default     = "localhost"  # Sensible default for local dev
}

# ❌ BAD: Hardcoded value
locals {
  base_domain = "mydomain.com"  # Will break in different environments
}
```

**Naming Conventions:**
- Setup script outputs: `<feature>_setup_script` (e.g., `docker_setup_script`)
- Metadata outputs: `metadata_blocks` (standard name)
- Port outputs: `docker_ports`, `ssh_port`, etc.
- Enable variables: `<feature>_enable` (e.g., `docker_enable`)

### 3. Dual-Mode Operation

The same module code works in both modes:

**Local Development Mode:**
```hcl
# In temp folder during push
module "docker" {
  source = "./module-docker"  # Local copy in temp dir
  base_domain = "dev.example.com"  # Injected by push script
}
```

**GitHub Production Mode:**
```hcl
# Future state - same module logic
module "docker" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/docker-module?ref=v1.0.0"
  base_domain = "prod.example.com"  # Still injected by push script
}
```

---

## Implementation Plan

### Phase 1: Local Module Copying (Immediate - Weeks 1-2)

#### Deliverable: `scripts/push-template-local.sh`

**Core Logic:**
1. Read `templates/<name>/modules.txt` to get module list
2. Copy module directories from `template-modules/modules/*-module/` to temp folder
3. Copy param files from `template-modules/params/` to temp folder
4. Perform environment substitution (BASE_DOMAIN, HOST_IP, etc.)
5. Auto-generate startup script assembly in `agent-params.tf`
6. Push self-contained template bundle to Coder

**Key Differences from `push-template-versioned.sh`:**
- No GitHub ref substitution (no `git::` sources to rewrite)
- Direct module directory copying instead of git fetch
- Module sources become local paths: `source = "./module-docker"`
- Same versioning, environment substitution, and metadata generation logic

**Script Structure:**
```bash
#!/bin/bash
# push-template-local.sh

# 1. Validate template and read modules.txt
# 2. Create temp directory structure
# 3. Copy template files
# 4. Copy modules from template-modules/modules/
# 5. Copy params from template-modules/params/
# 6. Rewrite module sources to local paths
# 7. Auto-inject startup script lines
# 8. Generate metadata-params.tf
# 9. Substitute environment variables
# 10. Push to Coder
```

**Example Module Copy:**
```bash
# For each line in modules.txt like "docker-params.tf"
# Extract module name: docker-params.tf -> docker-module
module_name=$(echo "$param_file" | sed 's/-params\.tf$/-module/')

# Copy entire module directory
cp -r "$MODULES_DIR/$module_name" "$TEMP_DIR/module-${module_name%-module}/"

# Module becomes available as: source = "./module-docker"
```

#### Testing Checklist
- [ ] modular-test template pushes successfully
- [ ] No GitHub fetches during terraform plan
- [ ] Workspace creation time < 30 seconds
- [ ] All modules execute in correct order
- [ ] Environment variables correctly substituted
- [ ] Can modify module and re-push without git commit

### Phase 2: Always-Load Pattern (Weeks 2-3)

#### Deliverable: Updated shared param files

**Current Problem:**
```hcl
# Causes UI flickering when toggled
module "ssh" {
  count = data.coder_parameter.ssh_enable.value ? 1 : 0
  source = "git::..."
}
```

**Solution (node-template pattern):**
```hcl
# Always loaded, no flickering
module "ssh" {
  source = "./module-ssh"  # Local path in temp dir
  ssh_enable = data.coder_parameter.ssh_enable.value
}

# Module internally handles enable flag
output "ssh_setup_script" {
  value = module.ssh.ssh_setup_script
}

output "ssh_port" {
  value = module.ssh.ssh_port
}
```

**Module Internal Logic:**
```hcl
# Inside ssh-module/main.tf
output "ssh_setup_script" {
  value = var.ssh_enable ? local.actual_setup_script : "# SSH disabled"
}

output "ssh_port" {
  value = var.ssh_enable ? var.ssh_port : null
}
```

#### Files to Update
- [ ] `template-modules/params/ssh-params.tf`
- [ ] `template-modules/params/docker-params.tf`
- [ ] `template-modules/params/git-params.tf`
- [ ] `template-modules/params/traefik-params.tf`
- [ ] Update main.tf dynamic blocks to check `!= null` instead of `[0]` indexing

#### Testing Checklist
- [ ] No UI parameter flickering when toggling features
- [ ] Module outputs always accessible (no array indexing)
- [ ] Disabled modules contribute empty/null outputs gracefully
- [ ] Terraform plan stable when toggling parameters

### Phase 3: Auto-Injection (Weeks 3-4)

#### Deliverable: Automated startup script assembly

**Current Problem:**
```hcl
# agent-params.tf - must manually maintain this list
startup_script = join("\n", [
  module.init_shell.setup_script,
  # INJECT_MODULES_HERE  <-- marker exists but not used
  module.git_identity.setup_script,
  try(module.docker[0].docker_setup_script, ""),  # Manual!
  try(module.ssh[0].ssh_setup_script, ""),         # Manual!
])
```

**Solution:**
```bash
# In push-template-local.sh

# Read modules.txt order
# For each module, detect setup script output
# Generate injection lines

# Example generated code:
startup_script = join("\n", compact([
  module.init_shell.setup_script,
  module.git_identity.setup_script,
  module.docker.docker_setup_script,  # Auto-generated
  module.ssh.ssh_setup_script,        # Auto-generated
  module.traefik.auth_setup_script,   # Auto-generated
]))
```

**Detection Logic:**
```bash
# For each module in modules.txt
# Read module-<name>/main.tf or <name>-params.tf
# Find output blocks matching *_script or *_setup_script pattern
# Generate: module.<name>.<output_name>

# Example:
# docker-params.tf has: output "docker_setup_script"
# Generate: module.docker.docker_setup_script
```

**Replacement in agent-params.tf:**
```bash
# Replace marker with generated lines
sed -i "s|# INJECT_MODULES_HERE|$generated_script_lines|" \
  "$TEMP_DIR/$TEMPLATE_NAME/agent-params.tf"
```

#### Testing Checklist
- [ ] Correct number of script outputs injected
- [ ] Script execution order matches modules.txt order
- [ ] No duplicate script entries
- [ ] Adding module to modules.txt automatically includes its scripts
- [ ] Removing module from modules.txt excludes its scripts

### Phase 4: Module Consolidation (Optional - Weeks 4-5)

**Goal:** Reduce indirection layers

**Current:** template → param file → module → code (3 layers)  
**Option A:** template → consolidated param+module → code (2 layers)  
**Option B:** Keep separate but optimize (module interface improvements)

**Recommendation:** Start with Option B, evaluate Option A later if complexity remains high.

---

## Migration Path: Local → GitHub

When ready to switch to GitHub distribution:

### Step 1: Tag Module Release
```bash
cd weekendstack
git tag -a modules/v1.0.0 -m "Stable module release"
git push origin modules/v1.0.0
```

### Step 2: Create `push-template-github.sh`
```bash
# Copy push-template-local.sh
cp scripts/push-template-local.sh scripts/push-template-github.sh

# Modify module source rewriting logic:
# Instead of: source = "./module-docker"
# Generate: source = "git::https://github.com/.../docker-module?ref=modules/v1.0.0"
```

### Step 3: Switch Push Script
```bash
# Development (fast iteration)
./scripts/push-template-local.sh modular-test

# Production (GitHub distribution)
./scripts/push-template-github.sh modular-test --ref modules/v1.0.0
```

### Step 4: Hybrid Mode (Best of Both)
```bash
# Push script accepts --mode flag
./scripts/push-template.sh modular-test --mode local    # Fast dev
./scripts/push-template.sh modular-test --mode github   # Production
./scripts/push-template.sh modular-test --mode github --ref modules/v1.1.0
```

**Implementation:**
```bash
case "$MODE" in
  local)
    # Copy modules to temp dir, use ./module-* paths
    ;;
  github)
    # Don't copy modules, inject git:: sources with ref
    # Still substitute environment variables
    ;;
esac
```

---

## Preserved Features

These elements are **working well** and will be kept unchanged:

### ✅ Incremental Versioning (v1, v2, v3...)
- Stored in `modules.txt` VERSION line
- Automatic collision detection and retry
- Remote version checking via `coder templates versions list`

### ✅ Git Ref Detection
- Auto-detects tags, branches, validates against origin
- Priority: `--ref` override → semver tag → main → current branch
- URL-encodes refs with `/` properly

### ✅ modules.txt Declarative System
- Single source of truth for template composition
- Line order = execution order
- Local override support (template-level param files win)
- Comment support for documentation

### ✅ Environment Variable Substitution
- Loads from `weekendstack/.env`
- Substitutes BASE_DOMAIN, HOST_IP, SSH_KEY_DIR, TRAEFIK_AUTH_DIR
- Applies to all templates consistently
- Dry-run mode shows substitution results

### ✅ Metadata Generation
- Auto-discovers metadata_blocks outputs from modules
- Generates metadata-params.tf with all available options
- Core metadata (CPU, RAM, disk) + module contributions
- Counts module-contributed metadata in logs

### ✅ Dry-Run Mode
- `--dry-run` flag previews all substitutions
- Shows ref detection results
- Displays environment variable values
- No actual push, safe for testing

---

## Directory Structure

```
config/coder/
├── docs/
│   └── modular-template-simplification-plan.md  (this file)
├── scripts/
│   ├── push-template-versioned.sh      (original - will deprecate)
│   ├── push-template-local.sh          (NEW - development mode)
│   └── push-template-github.sh         (FUTURE - production mode)
├── template-modules/
│   ├── modules/
│   │   ├── docker-module/
│   │   │   ├── main.tf                 (pure logic, no hardcoded values)
│   │   │   └── README.md
│   │   ├── ssh-module/
│   │   ├── traefik-routing-module/
│   │   └── ...
│   └── params/
│       ├── docker-params.tf            (bridges UI to module)
│       ├── ssh-params.tf
│       └── ...
└── templates/
    ├── modular-test/                   (PRIMARY TEST TARGET)
    │   ├── modules.txt                 (module manifest)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── agent-params.tf             (startup script assembly)
    ├── docker-template/
    ├── node-template/
    ├── vite-template/
    └── wordpress-template/
```

---

## Success Metrics

### Immediate Wins (Phase 1)
- [ ] Module changes testable without git commit/push
- [ ] Template push time < 30 seconds (no GitHub fetches)
- [ ] Can work offline/disconnected
- [ ] Zero GitHub API rate limit errors

### Medium-Term Wins (Phases 2-3)
- [ ] No UI parameter flickering
- [ ] Adding module requires editing only modules.txt (not agent-params.tf)
- [ ] Module execution errors easy to trace (single file per feature)
- [ ] Template composition clear from modules.txt alone

### Long-Term Wins (Phase 4)
- [ ] GitHub distribution mode available for production
- [ ] Modules versioned independently (`modules/v1.0.0`)
- [ ] Templates pull stable module releases
- [ ] Development still fast with local mode

---

## Testing Strategy

### Unit Testing (Per Phase)
- Script dry-run mode validates substitutions
- Manual verification of temp directory contents
- Terraform plan succeeds before push
- Push succeeds without errors

### Integration Testing (Full Workflow)
1. Modify a module (e.g., add debug output to docker-module)
2. Run `./scripts/push-template-local.sh modular-test`
3. Create workspace from new version
4. Verify module change visible in workspace
5. **Success:** No git commit needed

### Regression Testing (Existing Templates)
- docker-template (v93) still builds
- node-template (v123) still builds  
- vite-template (v64) still builds
- wordpress-template still builds
- All existing workspaces continue functioning

---

## Debugging Improvements

### Before (Current)
1. Edit module in `template-modules/modules/docker-module/main.tf`
2. Commit changes: `git commit -am "debug docker module"`
3. Push to GitHub: `git push origin main`
4. Wait for GitHub sync
5. Run push script (fetches from GitHub)
6. Push template to Coder
7. Create workspace to test
8. **Total time: 2-5 minutes per iteration**

### After (Phase 1 Complete)
1. Edit module in `template-modules/modules/docker-module/main.tf`
2. Run `./scripts/push-template-local.sh modular-test`
3. Create workspace to test
4. **Total time: 30-60 seconds per iteration**

### Iteration Speed Improvement: **4-8x faster**

---

## Risk Mitigation

### Risk 1: Breaking Existing Templates
**Mitigation:** 
- Test only with modular-test initially
- Keep push-template-versioned.sh functional during transition
- Migrate templates one at a time
- Document rollback procedure

### Risk 2: Module Interface Changes
**Mitigation:**
- Establish module contract upfront (see Architecture Principles)
- Validate all modules follow contract before Phase 1
- Create module validation script
- Update module README files with requirements

### Risk 3: Environment Variable Handling
**Mitigation:**
- Maintain existing substitution logic from push-template-versioned.sh
- Add validation that required vars are set
- Dry-run mode shows all substitutions
- Test with different .env configurations

### Risk 4: Startup Script Order
**Mitigation:**
- modules.txt order explicitly defines execution sequence
- Document order requirements (e.g., init-shell must be first)
- Add validation in push script to detect order issues
- Test script execution with debug logging

---

## Next Steps

### Week 1
- [ ] Create `scripts/push-template-local.sh` skeleton
- [ ] Implement module copying logic
- [ ] Test module source rewriting to local paths
- [ ] Verify environment substitution works

### Week 2  
- [ ] Add auto-injection logic for startup scripts
- [ ] Test with modular-test template
- [ ] Measure iteration time improvement
- [ ] Update shared param files to always-load pattern

### Week 3
- [ ] Complete metadata generation for local mode
- [ ] Test all module types (docker, ssh, git, traefik)
- [ ] Document new workflow in README
- [ ] Train on new push script usage

### Week 4
- [ ] Migrate docker-template to new system
- [ ] Migrate node-template to new system
- [ ] Design push-template-github.sh for future
- [ ] Validate module interface contract compliance

---

## Long-Term Vision

**Development Workflow:**
```bash
# Daily development - fast local iteration
./scripts/push-template-local.sh my-template

# Edit, test, edit, test... (seconds per iteration)
```

**Production Deployment:**
```bash
# Tag stable module release
git tag -a modules/v1.2.0 -m "Stable release"
git push origin modules/v1.2.0

# Push template with GitHub modules
./scripts/push-template-github.sh my-template --ref modules/v1.2.0

# Templates now pull from versioned GitHub modules
# Still fast (GitHub caches)
# Fully reproducible (pinned to tag)
```

**Best of Both Worlds:**
- Fast development iteration (local mode)
- Reliable production deployment (GitHub mode)
- Same module code works in both modes
- Environment values always injected correctly

---

## Conclusion

This plan eliminates the primary debugging friction (git commit/push cycle) while preserving all working features (versioning, modules.txt, environment substitution). The architecture supports seamless transition to GitHub distribution when ready, without requiring module rewrites. Implementation is phased to minimize risk and deliver immediate value.

**Immediate benefit:** 4-8x faster iteration during development  
**Long-term benefit:** GitHub-based distribution with version pinning  
**Cost:** ~2-4 weeks implementation + testing
