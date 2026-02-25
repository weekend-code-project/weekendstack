# Coder Template System v2

**Created:** 2026-01-11

This is a complete rewrite of the Coder template system with:
- **Build-time script compilation** - Startup scripts are composed at push time
- **Strict module isolation** - Each module is self-contained with clear contracts
- **Deterministic execution order** - Manifest controls script execution order
- **No host path dependencies** - Everything runs via labels and named volumes

## Directory Structure

```
v2/
├── scripts/           # Build and push scripts
│   └── push-template.sh
├── templates/         # Template definitions
│   └── base/          # Minimal base template
├── modules/           # Reusable modules (migrated one-by-one)
│   ├── platform/      # Core infrastructure (agent, container)
│   ├── feature/       # Optional features (auth, routing)
│   └── step/          # Startup script steps
├── helpers/           # Shared libraries
│   └── startup-lib.sh
└── dist/              # Build output (gitignored)
```

## Quick Start

```bash
# Push a template
./scripts/push-template.sh base

# Push with dry-run (see what would happen)
./scripts/push-template.sh --dry-run base
```

## Migration Status

See [modular-template-refactor-roadmap.md](../docs/modular-template-refactor-roadmap.md) for full progress.

| Module | Status | Notes |
|--------|--------|-------|
| base template | 🔄 In Progress | Minimal template for validation |
| coder-agent | ⏳ Pending | Core agent module |
| docker-workspace | ⏳ Pending | Container provisioning |
| startup-lib | ⏳ Pending | Helper functions |

## Architecture

### Module Contract

Each module provides:
- `main.tf` - Terraform resources
- `variables.tf` - Input variables
- `outputs.tf` - Required outputs (`agent_env`, `container_labels`, `startup_script_part`)
- `scripts/startup.part.sh` - Bash function for startup (optional)

### Startup Script Compilation

The push script:
1. Reads `manifest.json` from the template
2. Collects `startup.part.sh` from each module in order
3. Wraps each in a function with idempotency sentinel
4. Generates a single `startup.sh` with orchestrator

### No More Issues With:
- ❌ Scripts running before dependencies are ready
- ❌ Index page generating before server starts
- ❌ Modules with hidden cross-dependencies
- ❌ Hardcoded host paths
