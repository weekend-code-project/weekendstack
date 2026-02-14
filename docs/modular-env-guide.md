# Modular Environment Templates - Quick Reference

## Overview

The WeekendStack environment configuration has been modernized with a modular template system. Instead of a single 804-line .env.example file, environment variables are now organized into 65+ service-specific template files.

## Key Benefits

- **71% smaller .env files** for focused deployments (e.g., core profile: 228 lines vs 804)
- **Profile-aware configuration** - only includes variables for selected services
- **Easier maintenance** - one file per service
- **Custom docker-compose profile** - run `docker-compose up` without --profile flags
- **Fully tested** - 10 comprehensive tests ensure reliability

## Quick Start

### 1. Migration (One-Time)

The modular templates have already been generated from the monolithic .env.example:

```bash
# Templates are located at:
tools/env/templates/
├── global/         # System, paths, defaults (always included)
├── core/           # Essential services
├── ai/             # AI/LLM services
├── productivity/   # Document management, automation
├── dev/            # Development tools
├── media/          # Photos, music, books
├── automation/     # Home Assistant, Node-RED
├── monitoring/     # Uptime, performance monitoring
├── networking/     # Traefik, Pi-hole, tunnels
└── personal/       # Finance, recipes, fitness
```

### 2. Run Setup

The setup script now automatically uses modular templates:

```bash
./setup.sh

# Or quick mode
./setup.sh --quick
```

The setup process:
1. **Selects Profiles** - Interactive or quick mode
2. **Assembles Template** - Combines only needed service templates
3. **Generates .env** - Creates .env with secrets from assembled template
4. **Creates Custom Profile** - Generates docker-compose.custom.yml
5. **Sets COMPOSE_PROFILES=custom** - Enables simple `docker-compose up`

### 3. Start Services

No more --profile flags needed:

```bash
# Old way (still works)
docker-compose --profile core --profile ai up -d

# New way (simpler)
docker-compose up -d  # Uses custom profile automatically
```

## Architecture

### Assembly Flow

```
Selected Profiles → assemble-env.sh → .env.assembled → env-template-gen.sh → .env
                                   ↓
                          generate-custom-profile.sh → docker-compose.custom.yml
```

### File Structure

**Mappings (JSON)**
- `tools/env/mappings/profile-to-services.json` - Profile → Services mapping
- `tools/env/mappings/service-metadata.json` - Service display names, descriptions

**Scripts**
- `tools/env/scripts/assemble-env.sh` - Combines templates based on profiles
- `tools/env/scripts/generate-custom-profile.sh` - Creates custom docker-compose profile
- `tools/env/scripts/migrate-monolith.sh` - Splits monolithic .env.example (already run)

**Templates**
- `tools/env/templates/{profile}/{service}.env.example` - Individual service variables

## Manual Usage

### Assemble Environment for Specific Profiles

```bash
# Core services only
tools/env/scripts/assemble-env.sh --profiles "core" --output .env.assembled

# Multiple profiles
tools/env/scripts/assemble-env.sh --profiles "core,ai,productivity"

# Preview without writing
tools/env/scripts/assemble-env.sh --profiles "core" --preview
```

### Generate Secrets

```bash
# Uses .env.assembled if present, falls back to .env.example
tools/env-template-gen.sh

# Or specify template
tools/env-template-gen.sh .env.assembled .env
```

### Create Custom Profile

```bash
# Generate docker-compose.custom.yml
tools/env/scripts/generate-custom-profile.sh --profiles "core,ai"
```

### Validate Configuration

```bash
# Profile-aware validation (only checks enabled services)
tools/validate-env.sh

# Strict mode (validates all variables)
tools/validate-env.sh --strict
```

## Adding New Services

### 1. Create Service Template

```bash
# Create template file
cat > tools/env/templates/productivity/newservice.env.example << 'EOF'
# ============================================================================
# NEWSERVICE - Environment Variables
# ============================================================================
# Description of service
# ============================================================================

NEWSERVICE_PORT=8080
NEWSERVICE_SECRET=                               # <GENERATE> openssl rand -hex 32
NEWSERVICE_ADMIN_USER=${DEFAULT_ADMIN_USER}
NEWSERVICE_ADMIN_PASSWORD=${DEFAULT_ADMIN_PASSWORD}
EOF
```

### 2. Update Mappings

**profile-to-services.json:**
```json
{
  "productivity": [
    "nocodb",
    "n8n",
    "newservice"  // Add here
  ]
}
```

**service-metadata.json:**
```json
{
  "newservice": {
    "display_name": "New Service",
    "description": "What it does",
    "template": "productivity/newservice.env.example",
    "profile": "productivity"
  }
}
```

### 3. Test

```bash
# Test assembly
tools/env/scripts/assemble-env.sh --profiles "productivity" --preview | grep NEWSERVICE

# Run full test suite
tools/test/test-modular-env.sh
```

## Testing

Comprehensive test suite validates all functionality:

```bash
tools/test/test-modular-env.sh
```

**Tests Include:**
1. ✅ Assembly works for all 9 profiles
2. ✅ Global variables present in all profiles
3. ✅ Profile-specific variables correctly isolated
4. ✅ Secret generation works
5. ✅ Multi-profile assembly
6. ✅ Variable deduplication
7. ✅ Custom profile generation
8. ✅ Profile-aware validation
9. ✅ File size reduction (71% for core)
10. ✅ COMPOSE_PROFILES set to custom

## Migration Notes

- **Backward Compatible**: Original .env.example still exists as fallback
- **Automatic Detection**: Scripts detect modular templates and use them automatically
- **No Breaking Changes**: Existing .env files continue to work
- **Incremental Adoption**: Can switch profiles without full reconfiguration

## Troubleshooting

### Assembly produces empty file
Check that service exists in profile-to-services.json and metadata mappings

### Service variables missing
Ensure template file exists at path specified in service-metadata.json

### Custom profile not working
Verify docker-compose.custom.yml was generated and docker-compose.yml includes it

### Tests failing
Run `bash tools/test/test-modular-env.sh` to identify specific failure

## Performance Metrics

| Profile | Variables | Lines | Reduction |
|---------|-----------|-------|-----------|
| core | 33 | 228 | 71% |
| core+ai | 60+ | 307 | 62% |
| core+ai+productivity | 113+ | 507 | 37% |
| all | 200+ | 804 | 0% (original) |

## Files Reference

```
weekendstack/
├── .env.assembled          # Generated assembly (not committed)
├── .env                    # Final config (not committed)
├── docker-compose.custom.yml   # Custom profile (generated)
├── docker-compose.yml      # Includes custom profile
└── tools/
    ├── env-template-gen.sh # Updated for modular templates
    ├── validate-env.sh     # Updated for profile-aware validation
    ├── env/
    │   ├── mappings/
    │   │   ├── profile-to-services.json
    │   │   └── service-metadata.json
    │   ├── scripts/
    │   │   ├── assemble-env.sh
    │   │   ├── generate-custom-profile.sh
    │   │   └── migrate-monolith.sh
    │   └── templates/
    │       ├── global/
    │       ├── core/
    │       ├── ai/
    │       ├── productivity/
    │       ├── dev/
    │       ├── media/
    │       ├── automation/
    │       ├── monitoring/
    │       ├── networking/
    │       └── personal/
    ├── setup/lib/
    │   └── env-generator.sh  # Updated for assembly integration
    └── test/
        └── test-modular-env.sh  # Comprehensive test suite
```

## See Also

- [docs/setup-script-guide.md](setup-script-guide.md) - Full setup documentation
- [docs/profile-matrix.md](profile-matrix.md) - Service-to-profile mappings
- [tools/env/mappings/](../tools/env/mappings/) - JSON mapping files
