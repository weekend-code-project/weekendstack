# WeekendStack Tools

This directory contains utility scripts and the setup system for managing WeekendStack.

## Setup System

The `setup/` directory contains the modular library used by the main `setup.sh` script in the root directory. These modules provide:

- **common.sh** - Shared utility functions (logging, prompts, validation)
- **docker-auth.sh** - Multi-registry Docker authentication
- **profile-selector.sh** - Interactive service profile selection
- **env-generator.sh** - Environment configuration generation
- **directory-creator.sh** - Directory structure creation
- **cloudflare-wizard.sh** - Cloudflare Tunnel setup wizard
- **certificate-helper.sh** - CA certificate generation and installation
- **service-deps.sh** - Service dependency mapping
- **summary.sh** - Post-setup documentation generation

**For setup instructions, see:** [../docs/setup-script-guide.md](../docs/setup-script-guide.md)

---

## Utility Scripts

### `test_stack_health.sh`

Comprehensive health check that tests:
- Traefik container status and API accessibility
- Critical container health
- HTTP→HTTPS redirect middleware loading
- HTTP→HTTPS redirects for key services
- HTTPS access for services
- Container error states

**Usage:**
```bash
./tools/test_stack_health.sh
```

**Alternative:** Use the Makefile
```bash
make health    # Quick health check
make test      # Full system test
```

### `validate-env.sh`

Validates your `.env` file configuration:
- Checks for required variables
- Validates domain formats
- Verifies path configurations
- Checks port assignments

**Usage:**
```bash
./tools/validate-env.sh
```

### `list_stopped_containers.sh`

Lists all containers that are not running (Created, Exited, Dead states).

**Usage:**
```bash
./tools/list_stopped_containers.sh
```

**Alternative:** Use the Makefile
```bash
make ps        # List running containers
make status    # Show service status
```

---

## Common Scenarios

### Initial Setup

Use the interactive setup script:
```bash
./setup.sh
```

Or use the Makefile:
```bash
make setup
```

### Health Diagnostics

```bash
# Full health check
./tools/test_stack_health.sh

# Or use make
make health
make test
```

### Environment Validation

```bash
# Validate your .env configuration
./tools/validate-env.sh

# Validate docker-compose configuration
make validate
```

### Check Stopped Containers

```bash
# List stopped containers
./tools/list_stopped_containers.sh

# View all container status
make ps
make status
```

---

## Archived Scripts

The following scripts have been moved to `_trash/` as they've been replaced by the new setup system:

- `comprehensive_test.sh` - Replaced by `setup.sh` and `make test`
- `diagnose_lab.sh` - Diagnostic functionality now in `test_stack_health.sh`
- `env-template-gen.sh` - Replaced by `setup/lib/env-generator.sh`
- `generate_profile_matrix.py` - Replaced by `setup/lib/profile-selector.sh`
- `init-nfs-service.sh` - Replaced by setup system
- `list_lab_urls.py` - Functionality available via `make ports` and `make services`

---

## Quick Reference

### Using the Makefile

The root Makefile provides convenient shortcuts for all common operations:

```bash
make help              # Show all available commands
make setup             # Interactive setup
make start             # Start services
make stop              # Stop services
make restart           # Restart services
make status            # Service status
make logs              # View logs
make health            # Health check
make test              # System tests
make update            # Pull latest images and restart
make backup            # Backup configuration
```

**See:** Run `make help` for the complete command list.

### Direct Docker Compose

```bash
# Start all services
docker compose up -d

# Start specific profile
docker compose --profile dev up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f

# Check status
docker compose ps
```

### Environment Variables

Scripts and health checks use these `.env` variables:
- `LAB_DOMAIN` - Local domain suffix (e.g., `lab`)
- `BASE_DOMAIN` - External domain (e.g., `example.com`)
- `HOST_IP` - Host machine IP address
- `TRAEFIK_DOCKER_NETWORK` - Traefik network (default: `shared-network`)

### Troubleshooting

1. **Container won't start**: Check logs with `docker logs <container>` or `make logs-service SERVICE=<name>`
2. **Configuration issues**: Run `./tools/validate-env.sh` or `make validate`
3. **Health problems**: Run `./tools/test_stack_health.sh` or `make health`
4. **Need to reset**: Use `make clean` (keeps volumes) or see `./uninstall.sh`

---

## More Information

- **Setup Guide**: [docs/setup-script-guide.md](../docs/setup-script-guide.md)
- **Architecture**: [docs/architecture.md](../docs/architecture.md)
- **Services Guide**: [docs/services-guide.md](../docs/services-guide.md)
- **Main README**: [../README.md](../README.md)
