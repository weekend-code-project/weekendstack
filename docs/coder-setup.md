# Coder Development Environment Setup

## Overview

Coder provides cloud development environments (workspaces) accessible via browser. This setup uses Docker to run Coder locally with custom templates.

## Directory Structure

```
config/coder/
├── templates/              # Coder workspace templates
│   ├── modules/           # Reusable module files (shared across templates)
│   └── modular-docker/    # Example template
├── scripts/               # Template management scripts
│   ├── push-templates.sh  # Deploy templates to Coder
│   └── backup-templates.sh # Pull templates from Coder
└── README.md
```

## Configuration

### Environment Variables

Set in `.env` file:

```bash
# Coder configuration
CODER_VERSION=2.27.0
CODER_ACCESS_URL=http://host.docker.internal:7080  # Use host.docker.internal for workspace connectivity

# Directory paths (passed to templates via TF_VAR_*)
WORKSPACE_DIR=${FILES_BASE_DIR}/coder/workspace
TRAEFIK_AUTH_DIR=${CONFIG_BASE_DIR}/traefik/auth
SSH_KEY_DIR=/home/yourusername/.ssh  # REQUIRED: Set to your absolute SSH path
```

### Docker Compose Service

From `docker-compose.dev.yml`:

```yaml
coder:
  image: ghcr.io/coder/coder:${CODER_VERSION:-latest}
  container_name: coder
  privileged: true
  environment:
    CODER_ACCESS_URL: ${CODER_ACCESS_URL}
    CODER_PG_CONNECTION_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${CODER_DB}?sslmode=disable
    # Template path variables
    TF_VAR_workspace_dir: ${WORKSPACE_DIR}
    TF_VAR_traefik_auth_dir: ${TRAEFIK_AUTH_DIR}
    TF_VAR_ssh_key_dir: ${SSH_KEY_DIR}
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ${WORKSPACE_DIR}:/workspace
    - ${CODER_TEMPLATE_DIR}:/templates
    - ${TRAEFIK_AUTH_DIR}:/traefik-auth
    - ${SSH_KEY_DIR}:/host-ssh:ro
  ports:
    - "7080:7080"
```

## Initial Setup

### 1. Create Required Directories

The `coder-init` service automatically creates directories on first start:

```yaml
coder-init:
  image: alpine:latest
  command: >
    sh -c "
    echo 'Initializing Coder directories...' &&
    mkdir -p /workspace /templates &&
    chmod 777 /traefik-auth &&
    echo 'Traefik auth directory: /traefik-auth (777)' &&
    echo 'Directories initialized successfully'
    "
  volumes:
    - ${WORKSPACE_DIR}:/workspace
    - ${TRAEFIK_AUTH_DIR}:/traefik-auth
    - ${CODER_TEMPLATE_DIR}:/templates
```

### 2. Configure SSH Key Path

**REQUIRED**: Edit `.env` and set `SSH_KEY_DIR` to your absolute SSH directory:

```bash
# Linux example
SSH_KEY_DIR=/home/yourusername/.ssh

# macOS example
SSH_KEY_DIR=/Users/yourusername/.ssh

# WSL example
SSH_KEY_DIR=/home/yourusername/.ssh
```

⚠️ **Important**: Do NOT use `~` or `${HOME}` - Docker requires absolute paths.

### 3. Start Services

```bash
docker-compose up -d
```

### 4. Access Coder

1. Open browser to http://localhost:7080
2. Create admin account on first visit
3. Log in to Coder dashboard

### 5. Deploy Templates

```bash
cd config/coder/scripts
./push-templates.sh
```

## Template Management

### Modular Template System

Coder templates use a modular architecture that separates reusable modules from template-specific configuration.

**Key Principles:**
- **Shared modules** in `templates/modules/` (13 reusable components)
- **Template-specific** code in `templates/<template-name>/`
- **Bundling** happens automatically during push (modules stay separate locally)
- **Clean separation**: Local templates never have vendored `modules/` subdirectories

**Benefits:**
- ✅ **Clean Separation**: Template-specific vs. reusable code
- ✅ **No Duplication**: Modules defined once, used everywhere
- ✅ **Easy Updates**: Change a module, all templates benefit
- ✅ **Version Control**: Clear git diffs on what changed
- ✅ **Flexibility**: Templates can customize bundled modules
- ✅ **No External Dependencies**: Avoids Terraform module reference issues

### Available Modules

All modules are flat `.tf` files in `templates/modules/`:

| Module | Purpose | Size |
|--------|---------|------|
| `init-shell.tf` | Initialize home directory | ~40 lines |
| `install-docker.tf` | Install Docker | ~60 lines |
| `docker-config.tf` | Configure Docker daemon | ~50 lines |
| `ssh-copy.tf` | Copy SSH keys from host | ~30 lines |
| `ssh-setup.tf` | Configure SSH server | ~70 lines |
| `git-identity.tf` | Configure Git identity | ~40 lines |
| `install-github-cli.tf` | Install GitHub CLI | ~50 lines |
| `git-clone.tf` | Clone repository | ~60 lines |
| `install-node.tf` | Install Node.js | ~80 lines |
| `node-modules-persistence.tf` | Persistent node_modules | ~40 lines |
| `auth-protection.tf` | Traefik authentication | ~50 lines |
| `setup-server.tf` | Web server setup | ~60 lines |
| `run-startup-command.tf` | Execute startup command | ~30 lines |

Each module file follows a standard format:

```hcl
# =============================================================================
# MODULE: Module Name
# DESCRIPTION: What this module does
# =============================================================================

locals {
  module_script = <<-EOT
    #!/bin/bash
    # Module implementation
  EOT
}
```

### Push Templates to Coder

```bash
cd config/coder/scripts

# Push all templates
./push-templates.sh

# Push to specific Coder URL
./push-templates.sh http://coder.example.com

# View help
./push-templates.sh --help
```

**What happens:**
1. Reads clean template from `templates/`
2. Creates temporary directory
3. Bundles all modules from `templates/modules/`
4. Pushes combined template to Coder
5. Cleans up temp files
6. Leaves local template unchanged

### Pull Templates from Coder

```bash
cd config/coder/scripts

# Pull all templates
./backup-templates.sh

# Pull specific template
./backup-templates.sh <template-name>

# Pull to custom directory
./backup-templates.sh <template-name> /path/to/output
```

**What happens:**
1. Pulls template from Coder
2. Automatically removes bundled `modules/` folder
3. Keeps local templates clean
4. Preserves shared `templates/modules/` directory

### Creating a New Template

1. Create template directory:
   ```bash
   mkdir -p config/coder/templates/my-template
   ```

2. Create `main.tf` that references module locals:
   ```hcl
   terraform {
     required_providers {
       coder = {
         source  = "coder/coder"
         version = ">= 2.4.0"
       }
       docker = {
         source  = "kreuzwerker/docker"
         version = "~> 3.0"
       }
     }
   }

   resource "coder_agent" "main" {
     startup_script = join("\n", [
       local.init_shell,
       local.install_docker,
       local.git_identity,
       # ... select which modules you need
     ])
   }
   ```

3. Optionally organize into multiple `.tf` files:
   ```
   my-template/
   ├── main.tf         # Core: providers, agent, container
   ├── parameters.tf   # All coder_parameter blocks
   ├── README.md       # Template documentation
   ```

   **Multi-File Benefits:**
   - ✅ Terraform reads **all `.tf` files** in the directory
   - ✅ Merges them into a **single configuration**
   - ✅ Resources in one file can reference resources in another
   - ✅ Easier to navigate (find features faster)
   - ✅ Smaller files = less scrolling
   - ✅ Clear separation of concerns

   **Example Cross-File References:**

   In `parameters.tf`:
   ```hcl
   resource "random_password" "workspace_secret" {
     length = 24
   }
   ```

   In `main.tf`:
   ```hcl
   resource "coder_agent" "main" {
     env = {
       SECRET = random_password.workspace_secret.result
     }
   }
   ```

4. Push to Coder:
   ```bash
   cd config/coder/scripts
   ./push-templates.sh
   ```

5. Your local `templates/my-template/` stays clean with just your template files!

### Updating Modules

To update a module for all templates:

1. Edit the module file in `templates/modules/`:
   ```bash
   vim config/coder/templates/modules/install-docker.tf
   ```

2. Deploy updates to all templates:
   ```bash
   cd config/coder/scripts
   ./push-templates.sh
   ```

3. All templates using that module get the update automatically

### Template Development Rules

#### ✅ DO

- Commit `templates/modules/` to git (shared modules)
- Commit `templates/*/` to git (template-specific files)
- Use `./scripts/push-templates.sh` to deploy templates
- Keep local template directories clean (no vendored modules)
- Test templates before pushing to production
- Use meaningful workspace names
- Reference module locals in startup scripts

#### ❌ DON'T

- Commit vendored `modules/` subdirectories in template folders
- Edit modules in temp directories
- Push templates manually (always use push script)
- Store sensitive data in public workspaces

### How Bundling Works

When you push a template, the script:

1. **Reads** your clean template from `templates/`
2. **Creates** a temporary directory (`/tmp/coder_push_$$`)
3. **Copies** template files to temp directory
4. **Bundles** all 13 modules from `templates/modules/` into temp `modules/` subdirectory
5. **Pushes** the combined template to Coder
6. **Cleans up** temporary directory
7. **Leaves** your local template unchanged (no modules/ folder)

This approach:
- Keeps local development clean
- Avoids Terraform external module reference issues
- Ensures Coder has everything it needs in one place
- Makes git diffs clear and focused

When you backup templates, the script:

1. **Pulls** template from Coder
2. **Removes** bundled `modules/` folder automatically
3. **Saves** clean template to `templates/<name>/`
4. **Preserves** shared `templates/modules/` directory

## Using Coder

### Create a Workspace

1. Log in to Coder (http://localhost:7080)
2. Click "Create Workspace"
3. Select template (e.g., "modular-docker")
4. Fill in parameters:
   - Workspace name
   - Docker image
   - Exposed ports
   - Startup command
   - etc.
5. Click "Create"

### Access Workspace

Workspaces are accessible via:

- **VS Code in Browser**: Click "VS Code" button
- **SSH**: Use provided SSH command
- **Web Preview**: Access exposed ports via Traefik routing

### Workspace Lifecycle

- **Start**: Provisions container and runs startup script
- **Stop**: Stops container (preserves data)
- **Delete**: Removes container and associated resources
- **Rebuild**: Re-runs Terraform template (useful after template updates)

## Authentication & Routing

### Traefik Integration

Workspaces integrate with Traefik for routing and authentication:

- **Public workspaces** (`make_public=true`): No authentication
- **Private workspaces** (`make_public=false`): Basic auth required

Authentication files written to `${TRAEFIK_AUTH_DIR}`:
- `hashed_password-<workspace-name>`
- `dynamic-<workspace-name>.yaml`

See [traefik-setup.md](traefik-setup.md) for Traefik configuration.

### SSH Access

Templates mount `${SSH_KEY_DIR}` to copy your SSH keys into workspaces:

```hcl
mounts {
  source = var.ssh_key_dir
  target = "/host-ssh"
  read_only = true
}
```

Startup script copies keys:
```bash
mkdir -p ~/.ssh
cp /host-ssh/* ~/.ssh/ 2>/dev/null || true
chmod 600 ~/.ssh/id_* 2>/dev/null || true
```

## Path Configuration

### Template Variables

Templates use Terraform variables for portable paths:

```hcl
variable "workspace_dir" {
  description = "Base directory for workspace storage"
  type        = string
  default     = "/workspace"
}

variable "traefik_auth_dir" {
  description = "Directory for Traefik auth files"
  type        = string
  default     = "/traefik-auth"
}

variable "ssh_key_dir" {
  description = "SSH key directory to mount"
  type        = string
  default     = "~/.ssh"
}
```

### Passing Variables from Docker Compose

Environment variables with `TF_VAR_` prefix are automatically passed to Terraform:

```yaml
environment:
  TF_VAR_workspace_dir: ${WORKSPACE_DIR}
  TF_VAR_traefik_auth_dir: ${TRAEFIK_AUTH_DIR}
  TF_VAR_ssh_key_dir: ${SSH_KEY_DIR}
```

This makes templates portable across different installations.

## Troubleshooting

### Error: Workspace agent fails to connect (DNS resolution failure)

**Symptoms**: 
- Workspace creation succeeds but agent never connects
- Container logs show: `curl: (6) Could not resolve host: coder`
- Error message: `failed to download coder agent`

**Cause**: `CODER_ACCESS_URL` is set to `http://coder:7080` but workspace containers can't resolve the hostname `coder`

**Why this happens**: 
- Workspace containers run on the default Docker `bridge` network
- The `coder` hostname only resolves on the `coder-network` or `shared-network`
- The agent init script tries to download the Coder binary from `CODER_ACCESS_URL`
- DNS resolution fails because `coder` is not reachable from bridge network

**Fix**: 

1. Update `CODER_ACCESS_URL` in `.env`:
   ```bash
   # Change from:
   CODER_ACCESS_URL=http://coder:7080
   
   # To:
   CODER_ACCESS_URL=http://host.docker.internal:7080
   ```

2. Recreate the Coder container to apply the change:
   ```bash
   cd /opt/stacks/weekendstack
   docker rm -f coder-init coder
   docker compose up -d coder
   ```

3. Verify the new URL is set:
   ```bash
   docker exec coder printenv CODER_ACCESS_URL
   # Should output: http://host.docker.internal:7080
   ```

4. Delete and recreate any affected workspaces (updating won't fix existing containers)

**How it works**: 
- `host.docker.internal` is automatically configured in Docker containers to point to the host machine
- The Coder server listens on `0.0.0.0:7080`, accessible from both container networks and the host
- Workspace containers can reach Coder via `http://host.docker.internal:7080`

**Note**: This is the **server-side** `CODER_ACCESS_URL` that Coder uses to generate agent download URLs. This is different from the `coder_access_url` parameter in templates, which sets the `CODER_ACCESS_URL` environment variable inside workspace containers.

### Error: "invalid mount path: '~/.ssh' mount path must be absolute"

**Cause**: `SSH_KEY_DIR` in `.env` uses `~` or `${HOME}`

**Fix**: Set absolute path in `.env`:
```bash
SSH_KEY_DIR=/home/yourusername/.ssh
```

### Error: Template push fails

**Cause**: Coder CLI not authenticated or not accessible

**Fix**: 
1. Check Coder is running: `docker ps | grep coder`
2. Check logs: `docker logs coder`
3. Verify CLI: `docker exec coder coder version`

### Error: Permission denied writing to traefik-auth

**Cause**: Directory doesn't exist or has wrong permissions

**Fix**: The `coder-init` service should create it automatically. If not:
```bash
mkdir -p ./config/traefik/auth
chmod 777 ./config/traefik/auth
docker-compose restart coder
```

### Workspace fails to start

**Causes**:
- Docker image not available
- Invalid startup script
- Mount paths don't exist

**Debug**:
1. Check workspace logs in Coder UI
2. Check Coder logs: `docker logs coder`
3. Verify paths in `.env` exist
4. Test template: Try creating workspace with minimal configuration

### Template not appearing in Coder

**Cause**: Template not pushed or push failed

**Fix**:
```bash
cd config/coder/scripts
./push-templates.sh
```

Check Coder logs for errors:
```bash
docker logs coder | grep -i error
```

## CLI Usage

### Authenticate Coder CLI

From host (using copied binary):
```bash
/tmp/coder-cli login http://localhost:7080
```

From Coder container:
```bash
docker exec coder coder login http://localhost:7080
```

### List Templates

```bash
docker exec coder coder templates list
```

### List Workspaces

```bash
docker exec coder coder list
```

### SSH to Workspace

```bash
docker exec coder coder ssh <workspace-name>
```

## Best Practices

### Template Development

1. ✅ Keep modules in `templates/modules/` (shared)
2. ✅ Keep template-specific code in `templates/<name>/`
3. ✅ Use push script (don't manually vendor modules)
4. ✅ Test templates before pushing to production
5. ❌ Don't commit vendored `modules/` subdirectories

### Workspace Management

1. ✅ Stop workspaces when not in use (saves resources)
2. ✅ Use meaningful workspace names
3. ✅ Set appropriate parameters (don't over-provision)
4. ✅ Regular backups of important workspace data
5. ❌ Don't store sensitive data in public workspaces

### Security

1. ✅ Use private workspaces for sensitive projects
2. ✅ Regularly update Coder version
3. ✅ Use strong authentication
4. ✅ Limit exposed ports
5. ❌ Don't share workspace secrets

## Advanced Configuration

### Custom Docker Images

Build custom base images for workspaces:

```dockerfile
# Dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*
```

Reference in template:
```hcl
data "coder_parameter" "docker_image" {
  default = "my-custom-image:latest"
}
```

### Multi-Container Workspaces

Use Docker Compose in startup script:

```bash
cat > docker-compose.yml <<'EOF'
version: '3'
services:
  app:
    image: node:20
  db:
    image: postgres:15
EOF

docker-compose up -d
```

### Persistent Storage

Mount volumes for persistent data:

```hcl
resource "docker_volume" "workspace_data" {
  name = "coder-${data.coder_workspace.me.name}-data"
}

resource "docker_container" "workspace" {
  volumes {
    volume_name    = docker_volume.workspace_data.name
    container_path = "/data"
  }
}
```

## References

- [Coder Documentation](https://coder.com/docs)
- [traefik-setup.md](traefik-setup.md) - Traefik integration
- [deployment-guide.md](deployment-guide.md) - Production deployment
