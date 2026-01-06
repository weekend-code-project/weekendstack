# Modular Test Template

Baseline template for testing the new declarative module system.

## Purpose

This template serves as a clean baseline for incrementally adding and testing modules using the new `modules.txt` system. It starts with only the absolute minimum core modules and allows modules to be added one at a time to verify functionality and observe UI behavior.

## Current State

**Core Modules** (always loaded, defined in main.tf):
- `init_shell` - Shell initialization (.bashrc, .profile)
- `code_server` - VS Code Server web IDE

**Additional Modules** (none yet):
- modules.txt is currently empty
- Add modules one at a time for testing

## How to Add Modules

1. **Edit modules.txt** - Add one module filename per line
   ```
   docker-params.tf
   ```

2. **Update main.tf if needed** - Some modules require dynamic blocks:
   - Docker: No changes needed (privileged mode commented in main.tf)
   - SSH: Uncomment dynamic ports block
   - Traefik: Uncomment dynamic labels block

3. **Push template**:
   ```bash
   ./config/coder/scripts/push-template-versioned.sh modular-test
   ```

4. **Test workspace**:
   - Create new workspace OR update existing
   - Observe for UI flickering during parameter changes
   - Test module functionality
   - Document behavior

5. **Commit before next module**:
   ```bash
   git add .
   git commit -m "modular-test: Added [module-name] - [PASS/FAIL]"
   ```

## Module Testing Order (by risk level)

Recommended order from lowest to highest flickering risk:

1. ✅ **docker-params.tf** (medium risk) - Docker-in-Docker support
2. ✅ **metadata-params.tf** (medium-high risk) - Resource monitoring blocks
3. ✅ **setup-server-params.tf** (medium risk) - Development server
4. ⚠️ **ssh-params.tf** (VERY HIGH risk) - Known to cause checkbox toggling
5. ⚠️ **traefik-params.tf** (VERY HIGH risk) - Auth and routing labels
6. 🚨 **git-params.tf** (CRITICAL risk) - Known flickering module

## Module System Design

### Automatic Injection

The push script automatically:
1. Reads `modules.txt` line by line
2. Copies listed modules to temp directory (local first, else shared)
3. Generates startup script references from module outputs
4. Injects references into `agent-params.tf` at `# INJECT_MODULES_HERE` marker

### No Manual Script Composition

You never need to manually edit `agent-params.tf` startup script. Just add modules to `modules.txt` and the push script handles the rest.

### Module Naming Convention

Modules export script outputs following patterns:
- `{module_name}_script` (e.g., `docker_setup_script`)
- `{module_name}_{phase}_script` (e.g., `ssh_copy_script`, `ssh_setup_script`)

## Files in This Template

- **main.tf** - Core infrastructure (container, volumes, network)
- **variables.tf** - Template variables (base_domain, host_ip)
- **agent-params.tf** - Agent orchestration with injection marker
- **modules.txt** - Declarative module list (currently empty)
- **README.md** - This file

## Related Documentation

- [Modularization Plan](../../template-modularization-plan.md)
- [GitHub Project](https://github.com/orgs/weekend-code-project/projects/1)
- [Shared Modules](../../template-modules/params/README.md)

## Current Version

v1 - Baseline (core modules only, no parameters)
