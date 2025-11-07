# Node.js Workspace Template - Modular Architecture

A feature-rich Coder template for creating Node.js development workspaces with modular configuration, building on the shared modules architecture.

## Template Structure

```
node-template/
├── main.tf                      # Core Terraform configuration
├── variables.tf                 # Environment variables (paths)
├── resources.tf                 # Docker container and volumes
├── module-agent.tf             # Startup script orchestrator
├── module-init-shell.tf        # Home directory initialization
├── module-git.tf               # Git identity, cloning, GitHub CLI
├── module-ssh.tf               # SSH server with dynamic ports
├── module-docker.tf            # Docker-in-Docker integration
├── module-traefik-local.tf     # Traefik routing & authentication
├── module-node-version.tf      # Node version & installer strategy
├── module-node-tooling.tf      # Global tooling (TS/ESLint), pm setup
├── module-code-server.tf       # VS Code in browser
└── module-metadata.tf          # Workspace info display
```

## Module Pattern

Each `module-*.tf` file follows this pattern:

```hcl
# 1. Parameters - User-configurable options
data "coder_parameter" "feature_name" {
  name         = "feature_name"
  display_name = "Feature Name"
  type         = "bool"
  default      = false
  order        = 10
}

# 2. Module/Logic - Feature implementation
module "feature" {
  source = "git::https://...?ref=v0.1.0"
  # OR local logic using locals {}
}

# 3. Integration - Used by resources.tf or module-agent.tf
```

## Key Features

### Git Integration
- Configure Git identity (user.name, user.email)
- Clone repository with branch selection
- Optional GitHub CLI installation
- SSH key mounting from host

### Docker-in-Docker
- Full Docker Engine installation
- Registry mirror support
- Isolated networking
- Graceful failure handling

### Traefik Routing
- Automatic subdomain routing (workspace.domain.com)
- Optional authentication (public/private toggle)
- Dynamic Docker labels
- Middleware configuration

### SSH Access
- Dynamic port allocation
- Persistent host keys
- Optional public key authentication
- Configurable startup

### Development Tools
- VS Code Server (browser IDE)
- Setup Server (Express-based) — identical UX to shared static module. Options:
  - Serve Static Site (auto-generate welcome page)
  - Exposed Ports (list; first port used for preview)
  - Startup Command (runs detached, logs to /tmp/custom-startup.log)
- Preview Link Modes:
  - Local (Server IP): http://<server_host>:<port> — set Server IP/Host parameter
  - Traefik (External Subdomain): https://<workspace>.<domain>
  - Custom URL: arbitrary http(s) URL
- Logs: /tmp/express-server.log, PID: /tmp/express-server.pid
- Workspace validation

## Git Module Pattern (IMPORTANT)

Git-based modules **cannot use `count`** due to Terraform resolution order:

```hcl
# ❌ WRONG - Causes "Module not loaded" errors
module "docker" {
  count  = condition ? 1 : 0
  source = "git::https://..."
}

# ✅ CORRECT - Always load, conditionally execute
module "docker" {
  source = "git::https://..."
}

# Then in startup script:
startup_script = condition ? module.docker.script : ""
```

## Local vs Git Modules

### Git Modules (Preferred)
- **Used for**: git, ssh, docker, code-server, setup-server
- **Benefits**: Centralized, versioned, reusable
- **Pattern**: Always load module, conditional execution

### Local Implementation
- **Used for**: traefik (module-traefik-local.tf)
- **Reason**: Avoids Coder UI parsing issues with multiple git modules
- **Benefits**: Simplified debugging, single file, faster iteration

## Parameter Organization

Parameters are ordered for logical UI flow:

```
Order 10: make_public (Traefik)
Order 11: workspace_secret (Traefik, conditional)
Order 100+: Node-specific parameters
  100: node_install_strategy (system|volta|fnm|n)
  101: node_version (lts|22|20|18|16)
  102: node_package_manager (npm|pnpm|yarn)
  103: enable_typescript
  104: enable_eslint
Order 30: enable_docker (Docker)
Order 40-49: Git parameters
Order 50-59: SSH parameters
Order 60: code_server_enable
Order 99: metadata_blocks
```

## Startup Script Order

From `module-agent.tf`:

1. `init_shell` - Create directory structure
2. `git_identity` - Set Git config
3. `ssh_copy` - Mount host SSH keys
4. `git_integration` - Clone repo
5. `github_cli` - Install if needed (conditional)
6. `docker` - Install Docker (conditional)
7. `ssh_setup` - Configure SSH server (conditional)
8. `traefik_auth` - Setup auth (conditional)
9. `setup_server` - Start Express server and/or custom app (detached with nohup)

## Environment Variables

Set via `TF_VAR_*` in Coder container:

```bash
TF_VAR_workspace_dir=/path/to/workspaces
TF_VAR_ssh_key_dir=/path/to/ssh/keys
TF_VAR_traefik_auth_dir=/path/to/traefik/auth
```

## Testing

Push template:
```bash
bash config/coder/scripts/push-template-versioned.sh node-template
```

Create workspace:
```bash
coder create my-node-ws --template node-template
```

## Version History

- **v27**: Initial modular refactor (split from monolithic main.tf)
- **v28**: Docker module with count (broken)
- **v29**: Docker module fixed (conditional execution pattern)
- **v30**: Traefik with git modules (UI errors)
- **v31**: Traefik with correct module names (still errors)
- **v32**: Traefik local implementation (current, working)

## Troubleshooting

### Module Not Loaded Errors
- **Cause**: Using `count` on git-sourced modules
- **Fix**: Remove count, use conditional execution in startup script

### Traefik Not Routing
- **Check**: Docker labels applied (`docker inspect <container>`)
- **Check**: Traefik can see container (`docker logs traefik`)
- **Check**: Dynamic config files in traefik-auth directory

### Docker-in-Docker Not Working
- **Check**: Workspace container is privileged
- **Check**: `/var/run/docker.sock` is not mounted (we want isolated Docker)
- **Check**: `/tmp/dockerd.log` for daemon errors

## Contributing

When adding new Node-specific modules (e.g. package bootstrap, pnpm cache warm, node version pinning):

1. Create `module-{feature}.tf` file
2. Follow the module pattern (parameters → logic → integration)
3. Add to startup script in `module-agent.tf` if needed
4. Update this README
5. Test with `push-template-versioned.sh`
