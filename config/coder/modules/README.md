# Modules Directory

This directory contains reusable modules organized by category:

## Directory Structure

```
modules/
├── platform/      # Core infrastructure modules
│   ├── coder-agent/       # Coder agent configuration
│   └── docker-workspace/  # Container provisioning
│
├── feature/       # Optional feature modules
│   ├── ssh/              # SSH server access
│   ├── git/              # Git integration & cloning
│   ├── code-server/      # Web-based VS Code
│   ├── traefik/          # Traefik routing & auth
│   └── basic-auth/       # Password protection
│
└── step/          # Startup script steps
    ├── home-init/        # Initialize home directory
    ├── ports/            # Port configuration
    ├── index/            # Generate index.html
    └── user-command/     # Run custom startup command
```

## Module Contract

Each module must provide:

### Required Files
- `main.tf` - Terraform resources
- `outputs.tf` - Standard outputs

### Optional Files
- `variables.tf` - Input variables
- `scripts/startup.part.sh` - Startup script partial (for step modules)
- `README.md` - Documentation

### Standard Outputs
- `agent_env` - Map of environment variables for the agent
- `container_labels` - Map of Docker labels for routing
- `startup_script_part` - Bash code to run at startup (if applicable)

### Startup Script Convention
Script partials should define a function:
```bash
wcp__mod_<module_name>() {
    # Module-specific setup
}
```

The function will be called by the orchestrator with idempotency handling.

## Migration Status

| Module | Old Location | Status |
|--------|--------------|--------|
| coder-agent | coder-agent-module | ⏳ Pending |
| docker-workspace | docker-module | ⏳ Pending |
| ssh | ssh-module | ⏳ Pending |
| git | git-integration-module | ⏳ Pending |
| code-server | code-server-module | ⏳ Pending |
| traefik | traefik-routing-module | ⏳ Pending |
