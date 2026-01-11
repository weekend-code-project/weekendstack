# Modular Template System Refactor - Implementation Roadmap

> **🧠 LIVING MEMORY NOTE (for AI Assistant):**
> This document serves as living memory during the rebuild process. Update progress here as tasks complete.
> - **Current Session:** 2026-01-11 - Fresh rebuild in `/config/coder/v2/`
> - **Active Phase:** Phase 1/2 - Code-server module complete, ready for next module
> - **Last Completed:** 
>   - Created v2 folder structure with modules/, templates/, scripts/, helpers/
>   - Created simplified push-template.sh with module copying support
>   - Created base template with Coder agent + Docker container
>   - Created code-server module (feature/code-server)
>   - Template opens to /home/coder/workspace folder
>   - VS Code Desktop button disabled (web IDE only)
>   - Successfully pushed `new-modular-template` v4 to Coder
> - **Next Step:** Test workspace creation, then migrate SSH or Git module
> - **V2 Location:** `/opt/stacks/weekendstack/config/coder/v2/`
> - **Commits:** 2 commits on v0.2.0 branch

**Created:** 2026-01-11  
**Objective:** Transform the current partially-modular template system into a clean, composable architecture with build-time script concatenation and strict module isolation.

---

## Executive Summary

### Current State
- Templates have hardcoded cross-module references
- Host path dependencies (`/Users/nas/...` mounts)
- Auto-copy functions interfere with incremental testing
- No guaranteed startup script execution order
- Mixed concerns in monolithic template files

### Target State
- Self-contained modules with strict contracts (Terraform + script partial + outputs)
- Build-time manifest-driven composition
- Single orchestrator startup script with guaranteed execution order
- Label-based BasicAuth (no host bind mounts)
- Vendored modules per template (Coder sees fully compiled output)

### Key Technical Decisions
1. **One orchestrator script** per workspace (compiled from module partials)
2. **Module script isolation** via bash functions with sentinel-based idempotency
3. **Traefik BasicAuth via labels** (eliminate `/traefik-auth` mount)
4. **Manifest-defined module order** (`modules.json` per template)
5. **Build step generates** `dist/<template>/` with vendored modules + compiled scripts

---

## Implementation Phases

### Phase 0: Preparation & Validation ✅ COMPLETE
**Goal:** Establish baseline, disable broken auto-features, document current working state

> **Note:** We took a different approach - created a brand new v2 system rather than modifying the old one.
> The old system remains intact in `/config/coder/` for reference.
> The new v2 system is in `/config/coder/v2/` with a clean slate.

#### Task 0.1: Preserve Working Monoliths
- [x] Old templates preserved in `/config/coder/templates/` (unchanged)
- [x] New v2 system created in `/config/coder/v2/`
- [x] **Acceptance:** Reference templates exist, v2 is isolated

#### Task 0.2: Create New Push Script (v2 approach)
- [x] Created `v2/scripts/push-template.sh` - simplified, no auto-copy
- [x] Manifest-driven (reads `manifest.json` if present)
- [x] Variable substitution for `base_domain`, `host_ip`
- [x] **Acceptance:** Successfully pushed `new-modular-template` to Coder
- [ ] **Acceptance:** Only explicitly listed modules are copied

#### Task 0.3: Audit Current Module Inventory
- [ ] Document all modules in `template-modules/modules/` with purpose
- [ ] Identify which modules are "platform" vs "feature" vs "step"
- [ ] Map module dependencies (what outputs does each require?)
- [ ] **Acceptance:** Complete module inventory spreadsheet/table

---

### Phase 1: Build System Foundation 🏗️ BUILD
**Goal:** Create the build system that compiles manifests → templates

#### Task 1.1: Define Module Contract Standard
- [ ] Create `docs/module-contract-spec.md` documenting:
  - Required directory structure (`main.tf`, `variables.tf`, `outputs.tf`, `scripts/startup.part.sh`)
  - Required outputs (`agent_env`, `container_labels`, `startup_part`)
  - Script function naming convention (`wcp__mod_<module_id>`)
  - Sentinel pattern for idempotency
- [ ] **Acceptance:** Contract spec is complete and reviewable

#### Task 1.2: Create Manifest Schema
- [ ] Define `modules.json` format:
  ```json
  {
    "template_name": "base",
    "modules": [
      "ui/base",
      "platform/coder-agent",
      "step/home-init"
    ]
  }
  ```
- [ ] Document manifest keys and validation rules
- [ ] **Acceptance:** Schema documented with examples

#### Task 1.3: Build Script - Core Structure
- [ ] Create `scripts/build-template.sh` with:
  - Argument parsing (`--manifest <path>`, `--output <dir>`)
  - Manifest validation (check file exists, JSON is valid)
  - Output directory creation (`dist/<template>/`)
  - Logging framework
- [ ] Test with dry-run mode
- [ ] **Acceptance:** Script runs, validates manifest, creates output dirs

#### Task 1.4: Build Script - Module Vendoring
- [ ] Implement `vendor_modules()` function:
  - Read module list from manifest
  - Copy each module dir to `dist/<template>/modules/<module_id>/`
  - Preserve directory structure
  - Skip `.git` and temp files
- [ ] **Acceptance:** Modules correctly copied to dist/ with proper paths

#### Task 1.5: Build Script - Startup Script Compilation
- [ ] Implement `compile_startup_script()` function:
  - Read script partials in manifest order
  - Generate orchestrator header (helpers: `wcp_log`, `wcp__run_step_once`)
  - Wrap each partial in its module function
  - Generate `main()` that calls functions in order
  - Write to `dist/<template>/generated/startup.sh`
- [ ] **Acceptance:** Compiled startup.sh is syntactically valid bash

#### Task 1.6: Build Script - Template Assembly
- [ ] Generate `dist/<template>/main.tf`:
  - Provider declarations
  - Module source references (`source = "./modules/<id>"`)
  - Output merging pattern for env/labels
  - `startup_script = file("${path.module}/generated/startup.sh")`
- [ ] Generate `dist/<template>/variables.tf` (if needed)
- [ ] **Acceptance:** Generated Terraform is valid (`terraform validate`)

---

### Phase 2: Core Platform Modules 🧱 PLATFORM
**Goal:** Create the foundational platform modules that all templates need

#### Task 2.1: Module - `platform/docker-workspace`
- [ ] Create module structure:
  - `docker_volume.home_volume`
  - `docker_container.workspace` (name, hostname, entrypoint, network)
  - Input: `enable_dind` (boolean)
  - Input: `container_labels` (merged from other modules)
  - Output: `container_id`, `container_name`
- [ ] No script partial (pure infra)
- [ ] **Acceptance:** Module validates, outputs defined

#### Task 2.2: Module - `platform/coder-agent`
- [ ] Create module structure:
  - `coder_agent.main` resource
  - Metadata blocks (cpu, mem, disk, arch)
  - Input: `agent_env` (merged from other modules)
  - Input: `startup_script` (from compiled orchestrator)
  - Output: `agent_id`, `init_script`, `agent_env` (passthrough)
- [ ] **Acceptance:** Agent module validates, integrates with docker-workspace

#### Task 2.3: Module - `ui/base`
- [ ] Create module with `coder_parameter` resources:
  - `docker_image` (order=10, default="node:20-bookworm")
  - `exposed_ports` (order=20, default="8080")
  - `auto_generate_html` (order=30, default=true)
  - `startup_command` (order=40, default="")
  - `make_public` (order=50, default=false)
- [ ] Output: `agent_env` (with PORTS, MAKE_PUBLIC, etc.)
- [ ] **Acceptance:** UI renders in correct order, exports values

---

### Phase 3: Remove Host Dependencies 🚫 DECOUPLE
**Goal:** Eliminate all hardcoded host paths and file-based auth

#### Task 3.1: Module - `feature/basic-auth` (Label-Based)
- [ ] Create module structure:
  - `random_password.workspace_secret` resource
  - `coder_metadata` to display secret value
  - Input: `make_public` (from ui/base)
  - Output: `secret_value`, `secret_bcrypt_hash`, `auth_enabled`
  - Output: `container_labels` with:
    ```hcl
    "traefik.http.middlewares.${workspace}-auth.basicauth.users" = "coder:${bcrypt_hash}"
    ```
  - Output: `agent_env` with `WORKSPACE_SECRET`
- [ ] **Acceptance:** Module generates correct Traefik labels, no file writes

#### Task 3.2: Remove `/traefik-auth` Mount
- [ ] Audit all templates for `/traefik-auth` mounts
- [ ] Remove `mounts { source = "/Users/nas/.../traefik/auth" }` blocks
- [ ] Remove `apache2-utils` install from startup scripts
- [ ] Remove htpasswd generation logic
- [ ] **Acceptance:** No templates reference `/traefik-auth`, auth still works via labels

#### Task 3.3: Remove Workspace Host Bind Mount
- [ ] Audit templates for `/Users/nas/Coder/docker/workspaces/...` mounts
- [ ] Verify `docker_volume.home_volume` provides persistence
- [ ] Remove hardcoded workspace mounts
- [ ] **Acceptance:** Workspaces persist via named volumes only

---

### Phase 4: Startup Step Modules 🚀 STEPS
**Goal:** Create idempotent, scoped startup step modules

#### Task 4.1: Create Orchestrator Helper Library
- [ ] Create `template-modules/helpers/startup-lib.sh`:
  ```bash
  wcp_log() { ... }
  wcp__run_step_once() { ... }
  ```
- [ ] Document helper functions in contract spec
- [ ] **Acceptance:** Library is reusable and well-documented

#### Task 4.2: Module - `step/home-init`
- [ ] Create `scripts/startup.part.sh`:
  ```bash
  wcp__mod_home_init() {
    # Copy /etc/skel to /home/coder if first run
    # Set up .wcp directory
  }
  ```
- [ ] Add sentinel: `~/.wcp/steps/home-init.done`
- [ ] Output: `startup_part = file("${path.module}/scripts/startup.part.sh")`
- [ ] **Acceptance:** Function runs once, subsequent runs skip

#### Task 4.3: Module - `step/dind`
- [ ] Create conditional module (based on `enable_dind` param)
- [ ] Script partial:
  ```bash
  wcp__mod_dind() {
    # Install docker-ce if missing
    # Start dockerd in background if not running
    # Wait for docker socket readiness
  }
  ```
- [ ] Handle "run every start" vs "run once" (dockerd needs restart)
- [ ] **Acceptance:** Docker-in-docker works when enabled, skips cleanly when not

#### Task 4.4: Module - `step/ports`
- [ ] Create script partial:
  ```bash
  wcp__mod_ports() {
    # Parse PORTS env var
    # Export PORT as first port in list
    # Log derived PORT value
  }
  ```
- [ ] Output: `startup_part`
- [ ] **Acceptance:** PORT correctly derived from PORTS

#### Task 4.5: Module - `step/index`
- [ ] Create script partial:
  ```bash
  wcp__mod_index() {
    # Check if auto_generate_html is true
    # Generate index.html with PORT links if missing or default
    # Skip if custom index exists
  }
  ```
- [ ] Make idempotent (only write if file is default/missing)
- [ ] **Acceptance:** Index generates correctly, doesn't overwrite custom files

#### Task 4.6: Module - `step/user-command`
- [ ] Create script partial:
  ```bash
  wcp__mod_user_command() {
    # If STARTUP_COMMAND is set:
    #   Log command
    #   Execute in background with logging
    # Else:
    #   Log "No startup command"
  }
  ```
- [ ] Handle long-running processes (background with proper logging)
- [ ] **Acceptance:** Custom commands execute, don't block workspace readiness

---

### Phase 5: Routing & Preview Modules 🌐 ROUTING
**Goal:** Modularize Traefik routing and Coder app preview

#### Task 5.1: Module - `feature/traefik-preview`
- [ ] Create module structure:
  - Input: `workspace_name`, `owner_username`, `exposed_ports`, `auth_enabled`
  - Output: `container_labels` with router rules:
    ```hcl
    "traefik.http.routers.${ws}.rule" = "Host(`${ws}.${domain}`)"
    "traefik.http.services.${ws}.loadbalancer.server.port" = "${port}"
    ```
  - Conditional middleware attachment if auth enabled
  - `coder_app.preview` resource with dynamic URL
- [ ] **Acceptance:** Preview URL works, routing labels correct

#### Task 5.2: Module - `feature/public-toggle`
- [ ] Integrate with basic-auth module
- [ ] Ensure `make_public=true` disables auth middleware
- [ ] Test both public and private workspace access
- [ ] **Acceptance:** Public workspaces accessible without auth, private require password

---

### Phase 6: Specialized Templates 🎯 TEMPLATES
**Goal:** Create template manifests for different use cases

#### Task 6.1: Template - `base` (Minimal)
- [ ] Create `templates/base/modules.json`:
  ```json
  {
    "template_name": "base",
    "modules": [
      "ui/base",
      "platform/coder-agent",
      "platform/docker-workspace",
      "feature/basic-auth",
      "feature/traefik-preview",
      "step/home-init",
      "step/ports",
      "step/index",
      "step/user-command"
    ]
  }
  ```
- [ ] Build with `build-template.sh --manifest templates/base/modules.json`
- [ ] Push with `coder templates push dist/base/`
- [ ] Create test workspace
- [ ] **Acceptance:** Workspace provisions, preview works, auth works

#### Task 6.2: Template - `docker` (with DinD)
- [ ] Create `templates/docker/modules.json` (extends base + `step/dind`)
- [ ] Add `enable_dind` parameter default=true
- [ ] Build and test
- [ ] **Acceptance:** Docker-in-docker works, base features intact

#### Task 6.3: Module - `lang/node-install`
- [ ] Create module with:
  - `coder_parameter.node_version` (order=100)
  - Script partial to install nvm + node
  - Idempotent installation check
- [ ] Output: `agent_env` with node paths
- [ ] **Acceptance:** Node installs correctly, version matches param

#### Task 6.4: Module - `lang/node-project`
- [ ] Create script partial:
  ```bash
  wcp__mod_node_project() {
    # If package.json exists: npm install
    # If package-lock exists: use ci instead
    # Cache node_modules with sentinel
  }
  ```
- [ ] Handle git clone integration (run after clone if needed)
- [ ] **Acceptance:** npm install runs on first start, skips if node_modules current

#### Task 6.5: Template - `node`
- [ ] Create manifest with base + node modules
- [ ] Set default `startup_command = "npm run dev -- --host 0.0.0.0 --port $PORT"`
- [ ] Build and test with actual node project
- [ ] **Acceptance:** Node workspace auto-installs deps, runs dev server

#### Task 6.6: Module - `stack/wordpress-compose`
- [ ] Create script partial:
  ```bash
  wcp__mod_wordpress() {
    # If docker-compose.yml exists:
    #   docker compose up -d
    # Wait for WordPress readiness
    # Configure WP_HOME based on preview URL
  }
  ```
- [ ] Requires `step/dind`
- [ ] **Acceptance:** WordPress stack starts via compose

#### Task 6.7: Template - `wordpress`
- [ ] Create manifest with base + dind + wordpress
- [ ] Set exposed_ports default to "80,8080"
- [ ] Build and test
- [ ] **Acceptance:** WordPress workspace provisions and is accessible

---

### Phase 7: Network & Advanced Features 🔧 ADVANCED
**Goal:** Handle network management and advanced options

#### Task 7.1: Resolve `coder-net` Network Creation
- [ ] Audit where `docker network create coder-net` currently happens
- [ ] Options:
  - A) Create via Terraform `docker_network` resource (check for existing)
  - B) Ensure network exists in Weekend Stack bootstrap
  - C) Make network creation optional/conditional
- [ ] Remove network creation from startup scripts (too late)
- [ ] **Acceptance:** Network exists before containers start, no errors

#### Task 7.2: Module - `ui/advanced-options`
- [ ] Create dynamic parameters (conditional rendering):
  - "Show Advanced Options" (boolean, order=1000)
  - Advanced params only shown when true (using `count`)
- [ ] Document pattern for other modules
- [ ] **Acceptance:** UI is clean by default, advanced opts hide until toggled

#### Task 7.3: Improve Secret Rotation Policy
- [ ] Review `random_password.workspace_secret` keepers
- [ ] Options:
  - A) Remove `timestamp()` keeper (stable per workspace)
  - B) Keep rotation, but document behavior in metadata
- [ ] Test impact on existing workspaces
- [ ] **Acceptance:** Secret rotation behavior is intentional and documented

---

### Phase 8: Developer Experience 🎨 DX
**Goal:** Make the system easy to use, debug, and extend

#### Task 8.1: Build Script - Dry Run Mode
- [ ] Add `--dry-run` flag to `build-template.sh`
- [ ] Show what would be generated without writing files
- [ ] Display module order, script compilation preview
- [ ] **Acceptance:** Dry run shows accurate preview of build output

#### Task 8.2: Build Script - Watch Mode
- [ ] Add `--watch` flag to auto-rebuild on module changes
- [ ] Use `inotifywait` or similar to detect file changes
- [ ] Auto-push to Coder on successful build (optional `--auto-push`)
- [ ] **Acceptance:** Developer can edit modules and see changes quickly

#### Task 8.3: Startup Script - Enhanced Logging
- [ ] Improve `wcp_log` to include:
  - Timestamps
  - Color coding (if TTY)
  - Duration tracking per step
- [ ] Write consolidated log to `/tmp/wcp-startup.log`
- [ ] Add `coder_metadata` showing log file path
- [ ] **Acceptance:** Startup failures are easy to debug via logs

#### Task 8.4: Create Module Generator
- [ ] Create `scripts/new-module.sh --type <platform|feature|step|lang|stack> --name <id>`
- [ ] Generates skeleton module with contract-compliant structure
- [ ] Pre-populates README template
- [ ] **Acceptance:** New modules can be scaffolded in seconds

#### Task 8.5: Documentation - Module Catalog
- [ ] Create `docs/module-catalog.md` with:
  - Description of each module
  - Dependencies (what it requires from other modules)
  - Outputs provided
  - Example usage in manifests
- [ ] Auto-generate from module README files
- [ ] **Acceptance:** Catalog is complete and accurate

#### Task 8.6: Documentation - Template Development Guide
- [ ] Create `docs/creating-templates.md`:
  - How to create a new manifest
  - Module selection guidelines
  - Ordering best practices
  - Testing workflow
  - Troubleshooting common issues
- [ ] **Acceptance:** New contributor can create template from docs alone

---

### Phase 9: Migration & Cleanup 🧹 MIGRATE
**Goal:** Migrate existing templates and remove legacy code

#### Task 9.1: Migrate Existing Templates
- [ ] For each template in `templates/`:
  - Create equivalent manifest in new system
  - Build using new build script
  - Test parity with old template
  - Document any behavior differences
- [ ] **Acceptance:** All existing templates have new equivalents

#### Task 9.2: Deprecate Old Templates
- [ ] Rename old templates to `_old_<name>`
- [ ] Add deprecation notice in README
- [ ] Update push scripts to warn if pushing old-style template
- [ ] **Acceptance:** Old templates clearly marked deprecated

#### Task 9.3: Remove Auto-Copy Functions
- [ ] Delete `copy_referenced_modules()` from push scripts
- [ ] Remove git:: URL scanning logic (no longer needed)
- [ ] Simplify push script now that modules are vendored
- [ ] **Acceptance:** Push scripts are simpler, only handle vendored templates

#### Task 9.4: Clean Up template-modules/ Structure
- [ ] Reorganize modules into category subdirectories:
  ```
  template-modules/modules/
    platform/
    feature/
    step/
    lang/
    stack/
  ```
- [ ] Update build script to handle new paths
- [ ] **Acceptance:** Module organization matches logical categories

---

### Phase 10: Testing & Validation ✅ TEST
**Goal:** Ensure system works reliably across scenarios

#### Task 10.1: Integration Test Suite
- [ ] Create `tests/integration/test-build.sh`:
  - Test each manifest builds successfully
  - Validate generated Terraform
  - Check startup script syntax
- [ ] Run on every build script change
- [ ] **Acceptance:** All templates build without errors

#### Task 10.2: E2E Template Tests
- [ ] Create `tests/e2e/test-templates.sh`:
  - For each template: push, create workspace, verify features
  - Test auth works (public/private toggle)
  - Test preview URLs resolve
  - Test startup commands execute
- [ ] **Acceptance:** All templates provision successfully

#### Task 10.3: Module Isolation Tests
- [ ] Verify modules don't have hidden dependencies:
  - Build template with minimal module set
  - Ensure no errors about missing variables
  - Validate outputs are truly optional
- [ ] **Acceptance:** Modules can be composed freely without conflicts

#### Task 10.4: Startup Order Validation
- [ ] Create test that verifies execution order:
  - Add logging to each step function
  - Parse startup log
  - Confirm steps ran in manifest order
- [ ] **Acceptance:** Steps always execute in defined order

#### Task 10.5: Performance Benchmarks
- [ ] Measure build times for various template sizes
- [ ] Measure workspace startup times (baseline vs modular)
- [ ] Ensure modular system isn't significantly slower
- [ ] **Acceptance:** Build <5s, startup overhead <10s vs monolith

---

## Success Criteria

### System-Level Goals
- [ ] Zero hardcoded host paths in any template
- [ ] All templates build from manifests in <5 seconds
- [ ] Startup script execution order is deterministic
- [ ] Modules can be added/removed without breaking templates
- [ ] New template creation takes <5 minutes

### Quality Metrics
- [ ] All modules have README documentation
- [ ] 100% of modules follow contract spec
- [ ] All templates have integration tests
- [ ] Build script has --dry-run and --watch modes
- [ ] Developer guide enables independent template creation

### Migration Complete
- [ ] All legacy templates migrated to new system
- [ ] Old template system code removed
- [ ] Documentation reflects new system exclusively
- [ ] Team trained on new workflow

---

## Risk Mitigation

### Risk: Breaking existing workspaces
- **Mitigation:** Keep old templates available during migration, version template names (`base-v2`), test extensively before deprecation

### Risk: Module dependencies create coupling
- **Mitigation:** Enforce contract with validation, use integration tests to detect hidden deps, document all input/output requirements

### Risk: Build complexity becomes maintenance burden
- **Mitigation:** Keep build script simple, avoid over-engineering, document every function, create generator tools for common tasks

### Risk: Startup script becomes too large
- **Mitigation:** Modules should be focused, measure script size, consider breaking mega-templates into specialized variants

### Risk: Coder version compatibility
- **Mitigation:** Document Coder version requirements, test on Coder updates, avoid deprecated APIs, follow Coder best practices

---

## Appendix: Key Files Reference

### Build System
- `scripts/build-template.sh` - Main build orchestrator
- `scripts/new-module.sh` - Module scaffolding generator
- `template-modules/helpers/startup-lib.sh` - Shared bash functions

### Module Contract
- `main.tf` - Terraform resources
- `variables.tf` - Module inputs
- `outputs.tf` - Required: `agent_env`, `container_labels`, `startup_part`
- `scripts/startup.part.sh` - Bash function: `wcp__mod_<module_id>()`
- `README.md` - Module documentation

### Template Structure
- `templates/<name>/modules.json` - Manifest
- `dist/<name>/` - Build output (gitignored)
- `dist/<name>/modules/` - Vendored modules
- `dist/<name>/generated/startup.sh` - Compiled orchestrator
- `dist/<name>/main.tf` - Root template (generated)

### Documentation
- `docs/module-contract-spec.md` - Module interface specification
- `docs/module-catalog.md` - Available modules reference
- `docs/creating-templates.md` - Template development guide
- `docs/modular-template-refactor-roadmap.md` - This document

---

## Next Steps for New Chat Session

When resuming this work in a new chat:

1. **Share this document** as context
2. **Specify which phase** you want to tackle
3. **Reference task IDs** (e.g., "Let's implement Task 1.3: Build Script - Core Structure")
4. **Work incrementally** - complete and test each task before moving on
5. **Update checkboxes** as tasks complete to track progress

**Recommended Starting Point:** Phase 1 (Build System Foundation) - establishes the core infrastructure that everything else depends on.

---

*This roadmap is a living document. Update as implementation reveals new requirements or simplifications.*
