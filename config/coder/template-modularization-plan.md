# Coder Template Modularization Plan - Simplified Module System

## 1. Goals

**Primary Goals**:
- **Simplify template composition** through declarative module lists (`modules.txt`)
- **Maximize module reusability** across all templates while keeping modules self-contained
- **Eliminate manual startup script composition** through auto-injection during push
- **Prevent UI flickering** through consistent module patterns and self-validation
- **Enable incremental template building** by adding one module at a time with confidence
- **Maintain git ref auto-detection** for branch-aware module sourcing (already working)
- **Keep existing template versioning** (incremental v1, v2, v3...) unchanged

**Anti-Goals**:
- ❌ No backward compatibility needed (clean break, self-contained templates)
- ❌ No complex dependency graphs or validation frameworks
- ❌ No automatic circular dependency detection (keep it simple)
- ❌ No templating engines or code generation beyond simple injection

## 2. Module System Architecture

### Core Concepts

**Modules are Self-Contained Partials**:
- Each module is a single `*-params.tf` file containing parameters, module calls, and outputs
- Modules must export standardized script outputs (e.g., `docker_setup_script`, `ssh_setup_script`)
- Modules include metadata headers documenting: flickering risk, dependencies, outputs, load order
- Modules can be shared (in `template-modules/params/`) or template-specific (local)

**Templates Declare Module Lists**:
- Each template has a `modules.txt` file listing module filenames in execution order
- One filename per line (e.g., `docker-params.tf`, `ssh-params.tf`)
- Comments start with `#` for inline documentation
- Push script auto-detects source: local template dir first, else shared params dir

**Push Script Auto-Injects Modules**:
- Reads `modules.txt` and copies each module file to temp directory
- Generates startup script references from module list
- Injects generated script into `agent-params.tf` at `# INJECT_MODULES_HERE` marker
- Validates module script outputs and logs self-validation results

**agent-params.tf is Special**:
- Always required, always local (never listed in `modules.txt`)
- Orchestrates all other modules through startup script composition
- Contains injection marker where module scripts are inserted
- Handles agent configuration and environment variable setup

## 3. Current State (January 2026)

### Directory Structure
```
config/coder/
│
├── template-modules/
│   ├── modules/              # Git-based reusable modules (agent, docker, git, etc.) - 20 modules
│   └── params/               # Shared parameter definition files (7 files)
│       ├── agent-params.tf
│       ├── docker-params.tf
│       ├── git-params.tf
│       ├── metadata-params.tf
│       ├── setup-server-params.tf
│       ├── ssh-params.tf
│       └── traefik-params.tf
│
├── templates/
│   ├── docker-template/      # Production baseline (v93+)
│   ├── node-template/        # Full-featured Node.js (v123+) - has local overrides
│   ├── vite-template/        # Vite + React + TypeScript (v64)
│   ├── wordpress-template/   # WordPress + PHP/MySQL (v11)
│   └── test-template/        # Minimal testing baseline (v71)
│
├── scripts/
│   └── push-template-versioned.sh  # Current push script with auto-ref, substitution, overlay
│
└── template-modularization-plan.md  # This document
```

### Push Script Current Features
- ✅ Git ref auto-detection (tag > main > branch) with remote validation
- ✅ URL encoding for refs with special characters
- ✅ Variable substitution (`base_domain`, `host_ip`, `traefik_auth_dir`, `?ref=`)
- ✅ Version management (incremental v1, v2, v3...) with collision retry
- ✅ Shared param overlay (copies `*-params.tf` unless local override exists)
- ✅ Dry-run mode for preview
- ✅ Environment variable loading from workspace `.env` file

### Known Issues to Address
- ❌ Manual startup script composition in `agent-params.tf` (error-prone)
- ❌ No explicit module dependency declaration (implicit in file order)
- ❌ UI flickering from count-conditional modules and ternary operators
- ❌ Inconsistent module patterns across templates (some always-load, some count-based)
- ❌ Unused parameters defined but not passed to modules (bugs in #26, #29, #37)
- ❌ No validation that modules export expected script outputs
- ❌ Templates diverge over time (hard to keep synchronized)

## 4. Target Architecture

### Module Structure Standard

Every shared module in `template-modules/params/` follows this structure:

```hcl
# =============================================================================
# MODULE: SSH Server Configuration
# =============================================================================
# META: flickering_risk=very_high | depends=[] | provides=[ssh_port,docker_ports,ssh_enabled] | order=50
#
# OUTPUTS FOR INJECTION:
#   - ssh_setup_script: Main setup script for agent startup
#   - ssh_copy_script: SSH key copy operations (optional, run before setup)
#
# DEPENDENCIES:
#   - None (standalone module)
#
# ANTI-FLICKER PATTERN:
#   - Use always-load pattern (no count conditional)
#   - Module handles enable/disable logic internally
#   - Avoids checkbox toggling during workspace updates
#
# KNOWN ISSUES:
#   - See GitHub Issue #33 for flickering details
#
# SELF-VALIDATION:
#   - Validates SSH_KEY_DIR path exists
#   - Checks ssh_password parameter is set when enabled
#   - Logs validation results to startup script output
# =============================================================================

# Parameter definitions
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH Server"
  description  = "Start SSH server for direct terminal access"
  type         = "bool"
  default      = "false"
  mutable      = true
}

# Module declaration (always loaded - no count!)
module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  # Pass parameters
  ssh_enable_default = data.coder_parameter.ssh_enable.value
  # ... other inputs
}

# Outputs for injection
# Script output naming convention: {module_name}_script or {module_name}_{action}_script
output "ssh_setup_script" {
  value = module.ssh.ssh_setup_script
  description = "SSH server setup for agent startup"
}

output "ssh_copy_script" {
  value = module.ssh.ssh_copy_script
  description = "SSH key copy operations (run before setup)"
}

output "ssh_port" {
  value = module.ssh.ssh_port
  description = "SSH external port mapping"
}

output "docker_ports" {
  value = module.ssh.docker_ports
  description = "Docker port configuration for main.tf"
}
```

### Template Structure

Each template contains:

**Required Files**:
- `main.tf` - Core infrastructure (container, volumes, network)
- `variables.tf` - Template variables (base_domain, host_ip)
- `agent-params.tf` - Agent orchestration with injection marker
- `modules.txt` - Module list in load order

**Optional Files**:
- Any number of template-specific `*-params.tf` files
- `README.md` - Template documentation

**Example modules.txt**:
```txt
# Core Development Modules (loaded in startup script order)
docker-params.tf
metadata-params.tf
ssh-params.tf

# Template-Specific Modules
node-params.tf
node-modules-persistence-params.tf
```

**Example agent-params.tf with Injection Marker**:
```hcl
# =============================================================================
# Coder Agent - Startup Script Orchestrator
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Startup script assembled from module outputs (injected by push script)
  startup_script = join("\n", [
    # INJECT_MODULES_HERE
  ])
  
  # ... other agent config
}
```

### Push Script Enhanced Workflow

```bash
# 1. Parse modules.txt (skip comments, blank lines)
read_module_list() {
  grep -v '^#' modules.txt | grep -v '^[[:space:]]*$' | while read module; do
    echo "$module"
  done
}

# 2. Copy modules (local first, else shared)
copy_declared_modules() {
  while read module_file; do
    if [[ -f "$TEMPLATE_DIR/$module_file" ]]; then
      cp "$TEMPLATE_DIR/$module_file" "$TEMP_DIR/$TEMPLATE_NAME/"
      log "✓ $module_file (local)"
    elif [[ -f "$SHARED_PARAMS_DIR/$module_file" ]]; then
      cp "$SHARED_PARAMS_DIR/$module_file" "$TEMP_DIR/$TEMPLATE_NAME/"
      log "✓ $module_file (shared)"
    else
      log_error "✗ $module_file (NOT FOUND)"
      exit 1
    fi
  done < <(read_module_list)
}

# 3. Generate injection content
generate_injection() {
  while read module_file; do
    module_name="${module_file%-params.tf}"  # Strip -params.tf suffix
    # Try common output patterns
    echo "    try(module.${module_name}.${module_name}_setup_script, \"\"),"
    echo "    try(module.${module_name}.${module_name}_script, \"\"),"
  done < <(read_module_list)
}

# 4. Inject into agent-params.tf
inject_startup_scripts() {
  local injection_content=$(generate_injection)
  sed -i "s|# INJECT_MODULES_HERE|$injection_content|" "$TEMP_DIR/$TEMPLATE_NAME/agent-params.tf"
}
```

## 5. Module Naming Conventions & Standards

### Script Output Naming Convention

**Primary Pattern**: `{module_name}_script`
- Example: `docker_setup_script`, `ssh_setup_script`, `git_clone_script`

**Multi-Phase Pattern**: `{module_name}_{phase}_script`
- Example: `ssh_copy_script` (runs before `ssh_setup_script`)
- Use when module requires multiple execution phases in specific order

**Optional Outputs**: Modules without scripts are valid
- Example: `metadata-params.tf` might only provide parameter definitions
- Use `try(module.name.script, "")` pattern in injection to handle gracefully

### Module File Naming

**Shared Modules**: `{purpose}-params.tf`
- `docker-params.tf` - Docker-in-Docker support
- `ssh-params.tf` - SSH server configuration
- `git-params.tf` - Git integration
- `metadata-params.tf` - Resource monitoring blocks
- `setup-server-params.tf` - Development server startup
- `traefik-params.tf` - Traefik routing and auth

**Template-Specific Modules**: `{feature}-params.tf` or `{feature}-{aspect}-params.tf`
- `node-params.tf` - Node.js tooling
- `node-modules-persistence-params.tf` - Node modules volume
- `wordpress-params.tf` - WordPress configuration
- `vite-params.tf` - Vite-specific setup

**Reserved Names**: `agent-params.tf`
- Never listed in modules.txt
- Always present in template directory
- Contains module orchestration and injection marker

### Flickering Risk Levels

Modules document flickering risk in META header:

- `flickering_risk=low` - No parameters or immutable parameters only (safe)
- `flickering_risk=medium` - Mutable parameters but always-load pattern
- `flickering_risk=high` - Conditional visibility or multi-select parameters
- `flickering_risk=very_high` - Count-conditional loading or complex ternary logic

### Self-Validation Patterns

Every module should validate its inputs during startup:

```bash
# In module setup script
if [[ -z "$REQUIRED_VAR" ]]; then
  echo "❌ ERROR: REQUIRED_VAR not set for module-name"
  exit 1
fi

if [[ ! -d "$REQUIRED_PATH" ]]; then
  echo "⚠️  WARNING: $REQUIRED_PATH does not exist, skipping module-name"
  exit 0
fi

echo "✓ module-name validated successfully"
```

**Validation Results**: Logged to Coder agent startup output for debugging

## 6. Implementation Plan

### Phase 1: Standardize Shared Modules (Week 1)

**Goal**: Add metadata headers and consistent outputs to all shared param files

**Tasks**:
1. Add META header to each file in `template-modules/params/`:
   - `agent-params.tf` - Document orchestration role, 12 dependencies, flickering risk
   - `docker-params.tf` - Fix unused parameter bug (#26), add validation
   - `git-params.tf` - Fix unused parameter bug (#29), add validation
   - `metadata-params.tf` - Document multi-select flickering risk
   - `setup-server-params.tf` - Add port validation
   - `ssh-params.tf` - Document very high flickering risk, add path validation
   - `traefik-params.tf` - Document auth setup, add password validation

2. Standardize script output names:
   - Ensure all modules export `{name}_script` or `{name}_{phase}_script`
   - Document all outputs in META header
   - Add self-validation to each script output

3. Document module dependencies:
   - Create ASCII dependency diagram in each META header
   - List required inputs and optional inputs
   - Note recommended load order

**Acceptance Criteria**:
- All 7 shared param files have complete META headers
- All script outputs follow naming convention
- All modules include self-validation logic
- Documentation updated in `template-modules/params/README.md`

### Phase 2: Create Baseline Test Template (Week 1)

**Goal**: Build clean test template for incremental module addition

**Tasks**:
1. Create `templates/module-test-template/` directory
2. Create minimal `main.tf` (container, volume, network only)
3. Create `variables.tf` (base_domain, host_ip)
4. Create `agent-params.tf` with injection marker:
   ```hcl
   startup_script = join("\n", [
     # INJECT_MODULES_HERE
   ])
   ```
5. Create empty `modules.txt` with documentation comments
6. Create `README.md` explaining incremental testing approach
7. Push as v1, verify workspace creates successfully

**Acceptance Criteria**:
- Template pushes without errors
- Workspace creates successfully
- Agent starts with zero additional modules
- No UI flickering observed
- README documents testing workflow

### Phase 3: Enhance Push Script (Week 2)

**Goal**: Implement module list parsing and auto-injection

**Tasks**:
1. Remove `overlay_shared_params()` function (lines 222-245)
2. Add `read_module_list()` function:
   - Parse `modules.txt` line by line
   - Skip comments (`#`) and blank lines
   - Strip inline comments
   - Return array of module filenames

3. Add `copy_declared_modules()` function:
   - For each module in list, check local template dir first
   - If not found locally, check shared params dir
   - Error if module not found in either location
   - Log source for each module (local/shared)

4. Add `generate_injection_content()` function:
   - For each module, generate `try()` wrapped script references
   - Follow naming convention to find script outputs
   - Handle multi-phase scripts (copy_script before setup_script)

5. Add `inject_startup_scripts()` function:
   - Find `# INJECT_MODULES_HERE` marker in agent-params.tf
   - Replace with generated script references
   - Preserve indentation and formatting

6. Add `validate_module_outputs()` function:
   - Parse copied param files for output declarations
   - Check that expected script outputs exist
   - Warn if module has no script output (non-fatal)
   - Error if module referenced in modules.txt but file not found

**Acceptance Criteria**:
- Script parses modules.txt correctly
- Modules copied from correct source (local > shared)
- Injection marker replaced with script references
- Validation catches missing modules
- Logging shows module source and injection details
- Dry-run mode shows injection preview

### Phase 4: Incremental Module Testing (Weeks 3-4)

**Goal**: Add shared modules one at a time to identify flickering patterns

**Testing Workflow**:
1. Edit `module-test-template/modules.txt`, add ONE module filename
2. If module needs integration in `main.tf`, add required dynamic blocks
3. Push template: `./push-template-versioned.sh module-test-template`
4. Test workspace:
   - Create new workspace OR update existing
   - Observe UI during creation and updates
   - Check for checkbox toggling, field disappearing
   - Test parameter changes and interactions
5. Document results in template README or GitHub issue
6. Commit: `git commit -am "module-test: Added {module} - [PASS/FAIL]"`
7. Repeat for next module

**Module Addition Order** (by complexity/risk):
1. `docker-params.tf` (1 param, medium risk)
2. `metadata-params.tf` (1 param, medium-high risk)
3. `setup-server-params.tf` (3 params, medium risk)
4. `ssh-params.tf` (2 params, very high risk) ⚠️
5. `traefik-params.tf` (2 params, very high risk) ⚠️
6. `git-params.tf` (1 param, critical risk) ⚠️

**Acceptance Criteria**:
- Each module tested individually
- Flickering behavior documented
- Known issues filed or updated in GitHub
- Clean modules identified for production use
- Problematic modules flagged for refactoring

### Phase 5: Build Production Templates (Week 5)

**Goal**: Create production templates using tested modules

**Tasks**:
1. Create `module-node-template/` with modules.txt listing clean modules
2. Add template-specific `node-params.tf` and `node-modules-persistence-params.tf`
3. Test full template creation and updates
4. Create `module-docker-template/` as minimal baseline
5. Document template composition patterns in README

**Acceptance Criteria**:
- Production templates use modules.txt
- All modules auto-injected by push script
- No manual startup script composition
- Templates self-contained and portable
- Documentation complete

## 7. Benefits & Design Decisions

### Why This Approach?

**Simplicity**: 
- Module list is plain text, easy to read and edit by hand
- No YAML/JSON parsers needed (grep/awk sufficient)
- Auto-detection of module source eliminates need for prefixes
- Injection marker is simple comment replacement

**Maintainability**:
- Modules are self-contained with metadata headers
- Each module documents its own dependencies and risks
- Templates declare exactly what they need (no surprise overlays)
- Startup script composition is automatic (less manual error)

**Reusability**:
- Shared modules in `template-modules/params/` available to all templates
- Templates can override shared modules with local versions
- Module naming conventions make outputs predictable
- Self-validation ensures modules work correctly

**Debugging**:
- Clear logging shows which modules copied and from where
- Self-validation in modules catches configuration errors early
- Dry-run mode previews injection before push
- Each module logs validation results to agent output

### Design Decisions Explained

**Q: Why not YAML/JSON for modules.txt?**
A: Plain text is simpler to edit by hand, requires no additional tools, and is sufficient for a simple ordered list. The format is self-documenting.

**Q: Why auto-detect module source instead of requiring `shared:` or `local:` prefix?**
A: Reduces verbosity in modules.txt. Local-first precedence is intuitive (template-specific overrides shared). Less typing, less maintenance.

**Q: Why is agent-params.tf never in modules.txt?**
A: Agent orchestrates all other modules, so it must always be present. Making it implicit reduces cognitive load and prevents accidental omission.

**Q: Why use injection marker instead of generating entire agent-params.tf?**
A: Allows templates to customize agent configuration (env vars, metadata, etc.) while automating only the repetitive startup script composition. Balances automation with flexibility.

**Q: Why enforce naming convention for script outputs?**
A: Makes injection predictable and automated. Without convention, push script would need to parse each module to discover output names. Convention = simplicity.

**Q: Why include self-validation in modules?**
A: Catches configuration errors at workspace startup (when it matters) rather than at push time. Modules validate runtime environment, not just syntax. Better debugging experience.

**Q: Why load order matters?**
A: Some modules depend on others (e.g., node-modules-persistence needs package.json from git clone). Order in modules.txt = order in startup script. Explicit and controllable.

## 8. Migration from Current System

### Existing Templates

Current templates (docker, node, vite, wordpress) will continue to work with existing push script behavior until migrated.

**Migration Path** (per template):
1. Create `modules.txt` listing current `*-params.tf` files in startup script order
2. Add `# INJECT_MODULES_HERE` marker to `agent-params.tf`
3. Test with enhanced push script (push to Coder, verify workspace)
4. Iterate to remove unused modules or add missing ones
5. Document in template README

**No Backward Compatibility**: Each template is self-contained (push script copies everything to temp dir). Old and new templates can coexist. Migration is opt-in, not forced.

### Shared Modules

All 7 shared param files in `template-modules/params/` will be standardized with:
- META headers (already started in GitHub issues #23-#42)
- Consistent output naming
- Self-validation logic
- Dependency documentation

**Timeline**: Phase 1 (Week 1) standardizes all shared modules before any template migration.

## 9. Success Metrics

**Immediate** (Phases 1-3):
- [ ] All 7 shared modules have META headers and self-validation
- [ ] Push script supports modules.txt and auto-injection
- [ ] Baseline test template pushes and creates workspaces successfully
- [ ] Dry-run mode shows module injection preview

**Short-term** (Phases 4-5):
- [ ] All 6 shared modules tested individually for flickering
- [ ] Flickering patterns documented and mitigated
- [ ] At least 1 production template using new system (node or docker)
- [ ] Documentation complete and published

**Long-term** (Post-implementation):
- [ ] All templates migrated to modules.txt system
- [ ] No manual startup script composition anywhere
- [ ] Module library grows (more shared modules added)
- [ ] Templates easy to create (copy base, edit modules.txt, push)
- [ ] Flickering eliminated or predictable (known safe patterns)

---

**Prepared**: January 6, 2026  
**Status**: Planning Complete - Ready for Implementation
