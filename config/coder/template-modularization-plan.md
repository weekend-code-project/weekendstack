# Coder Template Modularization & Auto-Ref Plan (v0.1.1 Workstream)

## 1. Goals

**Original v0.1.1 Goals** (deferred until flickering issue resolved):
- Centralize reusable per-template Terraform module glue (`module-*.tf` files currently in `config/coder/templates/docker-template/`) into a shared location so multiple specialized templates can consume them without duplication.
- Preserve existing git-based reusable modules in `config/coder/template-modules/modules/` (unchanged).
- Introduce automatic Git ref resolution for git module sources (tag > main > current branch) during push, without committing moving refs.
- Maintain existing template versioning semantics (incremental v1, v2...) while enabling branch-aware module sourcing.
- Enable iterative development on a new branch `v0.1.1` and merge back to `main` when complete.

**Current Immediate Goals** (test-params-incrementally branch):
- **Identify and fix UI flickering** in Coder workspace templates (checkboxes toggling, fields disappearing during updates)
- Test modules incrementally starting from zero-parameter baseline to isolate flickering root cause
- Document findings for each module in GitHub issues (#23-#42)
- Fix identified bugs (unused parameters, unnecessary conditionals, ternary operators)
- Establish best practices for Terraform patterns that prevent UI flickering

## 2. Scope

**Current Scope** (test-params-incrementally branch):

In Scope:
- Incremental testing of all 17 modules to identify UI flickering patterns
- Creating comprehensive GitHub issues (#23-#42) documenting each module with full ASCII parameter dependency diagrams
- Testing modules one-by-one from simplest (0 params) to most complex (5 ternary operators)
- Fixing bugs: unused parameters, missing module inputs, conditional logic that causes re-evaluation
- Documenting flickering risk factors: ternary operators, conditional count, mutable parameters
- Establishing clean test-template baseline (v1 with zero parameters)

Out of Scope (for current flickering investigation):
- Full modularization architecture (deferred to v0.1.1 workstream)
- Automatic Git ref resolution
- Shared module overlay system
- Refactoring git modules themselves
- Changing Coder resource semantics

**Original v0.1.1 Scope** (deferred):

In Scope:
- Creating new shared folder for template-level Terraform composition files (the `module-*.tf` group) separate from any single template.
- Adjusting push workflow to inject or overlay these shared files into each template prior to pushing.
- Adding ephemeral substitution of `?ref=` in git module sources based on current Git context.
- Documentation updates (this plan, plus updates to `docs/coder-templates-guide.md`).
- Non-breaking incremental branch-based rollout.

Out of Scope (for v0.1.1 workstream):
- Refactoring the git modules themselves.
- Changing Coder resource semantics (e.g., `coder_agent`, `docker_container`).
- Introducing complex templating engines beyond simple variable substitution.

## 3. Current State Summary

**As of January 5, 2026** (origin/feature/services-cleanup branch):

### Module Architecture
- **Reusable Git Modules**: `config/coder/template-modules/modules/` - 20 Terraform modules (agent, docker, git, traefik, etc.)
  - Referenced via `git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/<module>?ref=PLACEHOLDER`
  - `PLACEHOLDER` is automatically replaced by push script with current git ref (tag > main > branch name)
  
- **Shared Parameter Files**: `config/coder/template-modules/params/` - 7 shared param files
  - `agent-params.tf` - Orchestrates startup script from all modules
  - `docker-params.tf` - Docker-in-Docker configuration
  - `git-params.tf` - Git integration (identity, clone, GitHub/Gitea CLI)
  - `metadata-params.tf` - Resource monitoring blocks
  - `setup-server-params.tf` - Development server configuration
  - `ssh-params.tf` - SSH server configuration
  - `traefik-params.tf` - Traefik routing and auth
  - These are **NOT automatically overlaid** - templates must explicitly include them

- **Template Structure**: Each template contains:
  - `main.tf` - Core infrastructure (container, volumes, base modules)
  - `variables.tf` - Template-level variables (base_domain, host_ip, etc.)
  - `*-params.tf` files - Parameter definitions and module calls (template-specific or copied from shared)
  - `agent-params.tf` - Always template-specific, orchestrates startup
  - Optional README.md

### Current Templates

**node-template** (v122+):
- Full-featured Node.js development environment
- Includes: git, docker, ssh, traefik, preview, setup-server, metadata
- Module files: 11 total (agent-params, git-params, docker-params, ssh-params, traefik-params, preview-params, setup-server-params, metadata-params, node-params, node-modules-persistence-params, main.tf)
- Status: Production-ready with known flickering issues

**vite-template**:
- Vite + React + TypeScript development
- Similar to node-template but with Vite-specific scaffolding
- Status: Working

**wordpress-template**:
- WordPress development environment with PHP/MySQL
- Includes custom wordpress-params.tf for database configuration
- Status: Working

**test-template** (v71):
- Minimal baseline for testing
- Only includes: agent, code-server, init-shell, docker, ssh, metadata, setup-server
- Purpose: Incremental module testing to identify flickering
- Status: Baseline restored, ready for testing

**docker-template**:
- Minimal Docker environment
- Similar to test-template but more production-focused
- Status: Minimal baseline

### Push Script (`push-template-versioned.sh`)

**Current Capabilities**:
1. **Git Ref Auto-Detection**:
   - Priority: Git tag (v*) > main branch > current branch name
   - Validates ref exists on remote origin
   - Fallback to `main` if ref not found
   - Override via `--ref <ref>` flag or `REF_OVERRIDE` env var

2. **Template Preparation**:
   - Creates temp directory `/tmp/coder-push-$$/<template>`
   - Copies template files to temp
   - ~~Overlays shared params from `template-modules/params/`~~ (REMOVED - templates must explicitly include files)
   - Template-local files take precedence over shared files

3. **Variable Substitution** (in temp directory only):
   - `?ref=PLACEHOLDER` → `?ref=<detected-git-ref>` in all git module sources
   - `base_domain` default value → `$BASE_DOMAIN` from .env
   - `host_ip` default value → `$HOST_IP` from .env
   - `traefik_auth_dir` default value → `$TRAEFIK_AUTH_DIR` from .env

4. **Version Management**:
   - Auto-increments version (v1, v2, v3...)
   - Stores version mapping in `.template_versions.json`
   - Retries with next version if push fails due to duplicate

5. **Flags**:
   - `--dry-run` - Show what would be pushed without executing
   - `--ref <ref>` - Override git ref detection
   - `--fallback <ref>` - Set fallback ref (default: main)

**Known Limitations**:
- Shared params are NOT automatically overlaid (removed feature)
- Templates must maintain their own param files
- No validation of module dependencies
- No circular dependency detection

### Available Modules (20 total)

**Core Infrastructure**:
- `coder-agent-module` - Coder agent with startup script orchestration
- `init-shell-module` - Shell initialization (.bashrc, .profile)
- `code-server-module` - VS Code Server web IDE
- `docker-module` - Docker-in-Docker support
- `metadata-module` - Resource monitoring blocks (CPU, RAM, disk)

**Git & Version Control**:
- `git-identity-module` - Git user.name and user.email configuration
- `git-integration-module` - Repository cloning
- `github-cli-module` - GitHub CLI installation
- `gitea-cli-module` - Gitea CLI installation

**Node.js Specific**:
- `node-tooling-module` - Node.js, npm/pnpm/yarn installation
- `node-version-module` - Node version selection (LTS, 22, 20, 18)
- `node-modules-persistence-module` - node_modules volume persistence

**Networking & Routing**:
- `traefik-routing-module` - Traefik labels, auth, preview buttons
- `preview-link-module` - Preview button (deprecated - use traefik-routing)
- `workspace-auth-module` - Basic auth (deprecated - use traefik-routing)
- `password-protection-module` - Password protection (deprecated - use traefik-routing)
- `routing-labels-test-module` - Test module for routing labels

**Server & Access**:
- `setup-server-module` - Development server startup/management
- `ssh-module` - SSH server configuration

**Utilities**:
- `coder-user-setup-module` - User environment setup

### Known Issues

**Flickering Problems**:
- Preview buttons may flicker or duplicate during workspace updates
- Traefik routing module conflicts with preview-link module
- Conditional module loading (`count` based on parameters) causes re-evaluation
- Ternary operators in startup scripts trigger parameter flickering

**Module Conflicts**:
- `traefik-routing-module`, `preview-link-module`, `workspace-auth-module`, `password-protection-module` overlap in functionality
- Multiple modules can create preview buttons (duplication)
- Auth setup scripts scattered across modules

**Integration Issues**:
- Circular dependencies between agent and traefik (agent needs traefik auth script, traefik needs agent_id)
- No automatic dependency resolution
- Templates must manually ensure correct module load order

## 4. How to Create a New Template

### Step 1: Create Template Directory

```bash
cd config/coder/templates
mkdir my-new-template
cd my-new-template
```

### Step 2: Create Core Files

**Required Files**:

1. **`main.tf`** - Core infrastructure
```hcl
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

# Workspace metadata
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# Docker provider
provider "docker" {}

# Container image
data "docker_registry_image" "main" {
  name = "codercom/enterprise-base:ubuntu"
}

resource "docker_image" "main" {
  name          = data.docker_registry_image.main.name
  pull_triggers = [data.docker_registry_image.main.sha256_digest]
  keep_locally  = true
}

# Workspace container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  
  hostname = data.coder_workspace.me.name
  
  # Connect to coder-network for Traefik routing
  networks_advanced {
    name = "coder-network"
  }
  
  # Agent init
  entrypoint = ["sh", "-c", replace(module.agent.agent_init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = ["CODER_AGENT_TOKEN=${module.agent.agent_token}"]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  # Home volume
  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
}

# Home volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = lower(data.coder_workspace.me.id)
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

# Base domain configuration
locals {
  actual_base_domain = var.base_domain
}

# Always-loaded modules (no conditional count)
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=PLACEHOLDER"
  
  workspace_folder = "/home/coder/workspace"
}

module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace"
}
```

2. **`variables.tf`** - Template variables
```hcl
variable "base_domain" {
  type        = string
  description = "Base domain for external access (e.g., example.com)"
  default     = "localhost"  # Will be replaced by push script
}

variable "host_ip" {
  type        = string
  description = "Host IP address for SSH and port forwarding"
  default     = "localhost"  # Will be replaced by push script
}
```

3. **`agent-params.tf`** - Agent configuration (always required)
```hcl
# =============================================================================
# Coder Agent - Startup Script Orchestrator
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "echo '[WORKSPACE] Starting workspace ${data.coder_workspace.me.name}'",
    "",
    module.init_shell.setup_script,
    # Add other module scripts here as needed
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = "http://host.docker.internal:7080"
  
  env_vars = {}
  
  metadata_blocks = []  # Or module.metadata.metadata_blocks if using metadata module
}
```

### Step 3: Add Optional Module Param Files

Copy and customize param files from `config/coder/template-modules/params/` or other templates:

**Git Integration** (`git-params.tf`):
```hcl
# Parameters for repository cloning
data "coder_parameter" "github_repo" {
  name         = "github_repo"
  display_name = "Repository URL"
  description  = "Git repository to clone"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 10
}

# Modules
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity-module?ref=PLACEHOLDER"
  
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
}

module "git_integration" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-integration-module?ref=PLACEHOLDER"
  
  repo_url         = data.coder_parameter.github_repo.value
  workspace_folder = "/home/coder/workspace"
}

# Update agent-params.tf to include git scripts:
# startup_script = join("\n", [
#   module.init_shell.setup_script,
#   module.git_identity.setup_script,
#   module.git_integration.clone_script,
#   ...
# ])
```

**Docker-in-Docker** (`docker-params.tf`):
```hcl
data "coder_parameter" "enable_docker" {
  name         = "enable_docker"
  display_name = "Enable Docker"
  description  = "Enable Docker-in-Docker for container development"
  type         = "bool"
  default      = "false"
  mutable      = false
  order        = 40
}

module "docker" {
  count  = data.coder_parameter.enable_docker.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/docker-module?ref=PLACEHOLDER"
}

# Update main.tf docker_container to add:
# privileged = data.coder_parameter.enable_docker.value

# Update agent-params.tf:
# data.coder_parameter.enable_docker.value ? try(module.docker[0].docker_setup_script, "") : ""
```

**SSH Server** (`ssh-params.tf`):
```hcl
data "coder_parameter" "ssh_enable" {
  name         = "ssh_enable"
  display_name = "Enable SSH"
  type         = "bool"
  default      = "true"
  mutable      = false
  order        = 50
}

module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  workspace_id    = data.coder_workspace.me.id
  enable_ssh      = data.coder_parameter.ssh_enable.value
  ssh_port_mode   = "auto"
  ssh_auto_port   = 0
  ssh_password    = ""
  host_ip         = var.host_ip
}

# Update main.tf docker_container to add:
# dynamic "ports" {
#   for_each = module.ssh.docker_ports != null ? [module.ssh.docker_ports] : []
#   content {
#     internal = ports.value.internal
#     external = ports.value.external
#     protocol = "tcp"
#   }
# }

# Update agent-params.tf:
# module.ssh.ssh_copy_script,
# module.ssh.ssh_setup_script,
```

**Traefik Routing** (`traefik-params.tf`):
```hcl
data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  type         = "string"
  default      = "traefik"
  mutable      = true
  order        = 30
  
  option {
    name  = "External (Traefik)"
    value = "traefik"
    icon  = "/icon/desktop.svg"
  }
  
  option {
    name  = "Internal (Coder Proxy)"
    value = "internal"
    icon  = "/icon/coder.svg"
  }
}

data "coder_parameter" "workspace_secret" {
  name         = "workspace_secret"
  display_name = "Workspace Password (Optional)"
  description  = "Leave blank for public access"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 31
}

locals {
  workspace_secret_value    = data.coder_parameter.workspace_secret.value
  traefik_auth_setup_script = try(module.traefik[0].auth_setup_script, "")
}

module "traefik" {
  count  = 1
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = local.actual_base_domain
  exposed_port     = "8080"
  preview_mode     = data.coder_parameter.preview_mode.value
  workspace_secret = local.workspace_secret_value
}

# Update main.tf docker_container to add:
# dynamic "labels" {
#   for_each = try(module.traefik[0].traefik_labels, {})
#   content {
#     label = labels.key
#     value = labels.value
#   }
# }

# Update agent-params.tf:
# local.traefik_auth_setup_script,
```

### Step 4: Push Template

```bash
cd /opt/stacks/weekendstack
bash config/coder/scripts/push-template-versioned.sh my-new-template
```

The push script will:
1. Detect current git ref (tag/branch)
2. Copy template to temp directory
3. Replace `?ref=PLACEHOLDER` with detected ref
4. Substitute `base_domain` and `host_ip` defaults from .env
5. Push to Coder as v1

### Step 5: Test & Iterate

1. Create workspace from new template
2. Test functionality
3. Make changes to template files
4. Push again (auto-increments to v2, v3, etc.)

### Module Integration Best Practices

**✅ DO**:
- Always load core modules (agent, init_shell, code_server) without `count`
- Use `try()` wrapper for conditional modules: `try(module.name[0].output, "")`
- Test parameters incrementally to identify flickering
- Document module dependencies in comments
- Use `mutable = false` for parameters that affect infrastructure

**❌ DON'T**:
- Use conditional `count` on modules that affect UI parameters (causes flickering)
- Create circular dependencies between modules
- Use multiple modules that provide same functionality (traefik vs preview-link)
- Forget to add module scripts to agent startup_script
- Use ternary operators in startup script joins (causes re-evaluation)

### Common Module Combinations

**Minimal Template**:
- agent, init_shell, code_server

**Development Template**:
- agent, init_shell, code_server, git, docker, ssh, metadata

**Full-Featured Template**:
- agent, init_shell, code_server, git, docker, ssh, traefik, setup-server, metadata, node/wordpress/vite-specific modules

## 5. Push Script Reference

### Auto-Ref Resolution Policy

The push script automatically detects and uses the appropriate git reference:

**Priority Order**:
1. `REF_OVERRIDE` environment variable (highest priority)
2. `--ref <ref>` command line flag
3. Git tag matching `v*` pattern (if HEAD is exactly on tag)
4. Branch name `main`
5. Current branch name
6. Fallback to `main` (if ref not found on remote)

**Validation**:
- All refs are validated against `git ls-remote origin <ref>`
- URL-encodes refs with special characters (slashes, etc.)
- Aborts if both detected ref and fallback ref are missing on remote

**Usage Examples**:
```bash
# Use auto-detected ref (current branch/tag)
./push-template-versioned.sh my-template

# Override with specific ref
./push-template-versioned.sh --ref v0.2.0 my-template

# Use environment variable
REF_OVERRIDE=feature/test ./push-template-versioned.sh my-template

# Dry-run to see what would happen
./push-template-versioned.sh --dry-run my-template

# Custom fallback ref
./push-template-versioned.sh --fallback develop my-template
```

### Variable Substitution

The push script performs the following substitutions **in the temp directory only** (repo files unchanged):

1. **Git Module References**:
   - Pattern: `git::https://github.com/weekend-code-project/weekendstack.git//<path>?ref=PLACEHOLDER`
   - Replaced with: `?ref=<detected-ref>` (URL-encoded)
   - Affects: All `.tf` files

2. **base_domain Variable**:
   - Pattern: `variable "base_domain"` with `default = "..."`
   - Replaced with: `default = "${BASE_DOMAIN}"` from .env file
   - Affects: `variables.tf` files

3. **host_ip Variable**:
   - Pattern: `variable "host_ip"` with `default = "..."`
   - Replaced with: `default = "${HOST_IP}"` from .env file
   - Affects: `variables.tf` files

4. **traefik_auth_dir Variable**:
   - Pattern: `variable "traefik_auth_dir"` with `default = "..."`
   - Replaced with: `default = "${TRAEFIK_AUTH_DIR}"` from .env file
   - Affects: `variables.tf` files

### Version Management

**Automatic Versioning**:
- Each template maintains independent version counter (v1, v2, v3...)
- Version state stored in `.template_versions.json`
- Auto-increments on each push
- Retries with next version if Coder rejects due to duplicate

**Version File Format** (`.template_versions.json`):
```json
{
  "node-template": 122,
  "test-template": 71,
  "docker-template": 82
}
```

### Push Workflow

1. **Parse Arguments**:
   - Extract flags (`--dry-run`, `--ref`, `--fallback`)
   - Get template name

2. **Load Environment**:
   - Read `.env` file for `BASE_DOMAIN`, `HOST_IP`, etc.
   - Set defaults if not found

3. **Detect Git Ref**:
   - Check for override (env var or flag)
   - Detect tag/branch
   - Validate on remote
   - Apply fallback if needed

4. **Prepare Template**:
   - Create temp directory `/tmp/coder-push-$$/<template>`
   - Copy all template files
   - ~~Overlay shared params~~ (REMOVED)

5. **Substitute Variables**:
   - Replace `?ref=PLACEHOLDER` with detected ref
   - Update `base_domain`, `host_ip`, `traefik_auth_dir` defaults

6. **Determine Version**:
   - Read current version from `.template_versions.json`
   - Increment by 1

7. **Push to Coder**:
   - Execute `coder templates push`
   - Retry with next version if duplicate error
   - Update `.template_versions.json` on success

8. **Cleanup**:
   - Remove temp directory

### Flags Reference

| Flag | Description | Example |
|------|-------------|---------|
| `--dry-run` | Show what would be pushed without executing | `./push.sh --dry-run node-template` |
| `--ref <ref>` | Override git ref detection | `./push.sh --ref v0.2.0 node-template` |
| `--fallback <ref>` | Set fallback ref if detected not found | `./push.sh --fallback develop node-template` |
| `-h, --help` | Show help message | `./push.sh --help` |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `REF_OVERRIDE` | Override git ref detection | (none) |
| `FALLBACK_REF` | Fallback ref if detected not found | `main` |
| `BASE_DOMAIN` | Base domain for workspaces | `localhost` |
| `HOST_IP` | Host IP for SSH/ports | `localhost` |
| `TRAEFIK_AUTH_DIR` | Traefik auth directory path | `/opt/stacks/weekendstack/config/traefik/auth` |

## 6. Module Reference Guide

### Core Infrastructure Modules

#### `coder-agent-module`
**Purpose**: Creates the Coder agent that runs inside the workspace container.

**Inputs**:
- `arch` - Architecture (data.coder_provisioner.me.arch)
- `os` - Operating system ("linux")
- `startup_script` - Bash script to run on workspace startup
- `git_author_name` - Git user.name
- `git_author_email` - Git user.email
- `coder_access_url` - Coder server URL
- `env_vars` - Map of environment variables
- `metadata_blocks` - Resource monitoring blocks

**Outputs**:
- `agent_id` - Agent ID (used by other modules)
- `agent_token` - Agent token (for container env)
- `agent_init_script` - Init script (for container entrypoint)

**Usage**:
```hcl
module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  startup_script = join("\n", [
    "#!/bin/bash",
    module.init_shell.setup_script,
    module.git_identity.setup_script,
    # ... other module scripts
  ])
  
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = "http://host.docker.internal:7080"
  env_vars         = {}
  metadata_blocks  = []
}
```

#### `init-shell-module`
**Purpose**: Shell initialization (.bashrc, .profile setup).

**Inputs**:
- `workspace_folder` - Workspace directory path

**Outputs**:
- `setup_script` - Shell init script

**Usage**:
```hcl
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=PLACEHOLDER"
  
  workspace_folder = "/home/coder/workspace"
}
```

#### `code-server-module`
**Purpose**: VS Code Server web IDE.

**Inputs**:
- `agent_id` - Coder agent ID
- `workspace_start_count` - Start count for conditional creation
- `folder` - Folder to open (optional)
- `order` - Display order (optional)
- `settings` - VS Code settings map (optional)
- `extensions` - Extension IDs list (optional)

**Outputs**:
- `code_server_id` - Code server app ID

**Usage**:
```hcl
module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace"
  extensions            = ["github.copilot", "dbaeumer.vscode-eslint"]
}
```

#### `docker-module`
**Purpose**: Docker-in-Docker support.

**Inputs**: None

**Outputs**:
- `docker_setup_script` - Docker installation script

**Usage**:
```hcl
data "coder_parameter" "enable_docker" {
  name    = "enable_docker"
  type    = "bool"
  default = "false"
}

module "docker" {
  count  = data.coder_parameter.enable_docker.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/docker-module?ref=PLACEHOLDER"
}

# In main.tf docker_container:
resource "docker_container" "workspace" {
  privileged = data.coder_parameter.enable_docker.value
  # ...
}

# In agent startup_script:
# data.coder_parameter.enable_docker.value ? try(module.docker[0].docker_setup_script, "") : ""
```

#### `metadata-module`
**Purpose**: Resource monitoring blocks (CPU, RAM, disk).

**Inputs**:
- `selected_blocks` - List of blocks to show
- `custom_metadata` - Additional metadata blocks (optional)

**Outputs**:
- `metadata_blocks` - List of metadata block configs

**Usage**:
```hcl
data "coder_parameter" "metadata_blocks" {
  name    = "metadata_blocks"
  type    = "list(string)"
  default = jsonencode(["cpu", "ram", "disk"])
}

module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata-module?ref=PLACEHOLDER"
  
  selected_blocks = jsondecode(data.coder_parameter.metadata_blocks.value)
  custom_metadata = []
}

# Pass to agent:
# metadata_blocks = module.metadata.metadata_blocks
```

### Git & Version Control Modules

#### `git-identity-module`
**Purpose**: Git user.name and user.email configuration.

**Inputs**:
- `git_author_name` - Git user name
- `git_author_email` - Git email

**Outputs**:
- `setup_script` - Git config script

**Usage**:
```hcl
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity-module?ref=PLACEHOLDER"
  
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
}
```

#### `git-integration-module`
**Purpose**: Repository cloning.

**Inputs**:
- `repo_url` - Git repository URL
- `workspace_folder` - Target folder

**Outputs**:
- `clone_script` - Git clone script

**Usage**:
```hcl
data "coder_parameter" "github_repo" {
  name    = "github_repo"
  type    = "string"
  default = ""
}

module "git_integration" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-integration-module?ref=PLACEHOLDER"
  
  repo_url         = data.coder_parameter.github_repo.value
  workspace_folder = "/home/coder/workspace"
}
```

#### `github-cli-module`
**Purpose**: GitHub CLI installation.

**Outputs**:
- `install_script` - gh installation script

**Usage**:
```hcl
module "github_cli" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/github-cli-module?ref=PLACEHOLDER"
}
```

#### `gitea-cli-module`
**Purpose**: Gitea CLI installation.

**Outputs**:
- `install_script` - tea installation script

**Usage**: Same as github-cli-module

### Networking & Routing Modules

#### `traefik-routing-module` (RECOMMENDED)
**Purpose**: Traefik labels, authentication, and preview buttons.

**Inputs**:
- `agent_id` - Coder agent ID
- `workspace_name` - Workspace name
- `workspace_owner` - Owner username
- `workspace_id` - Workspace ID
- `workspace_owner_id` - Owner ID
- `workspace_start_count` - Start count
- `domain` - Base domain
- `exposed_port` - Port to expose
- `preview_mode` - "internal" or "traefik"
- `workspace_secret` - Password (empty = public)

**Outputs**:
- `traefik_labels` - Docker labels map
- `workspace_url` - External URL
- `preview_url` - Preview URL
- `auth_setup_script` - Auth setup script
- `auth_enabled` - Whether auth is enabled

**Usage**:
```hcl
data "coder_parameter" "preview_mode" {
  name    = "preview_mode"
  default = "traefik"
  option { name = "External (Traefik)"; value = "traefik" }
  option { name = "Internal (Coder)"; value = "internal" }
}

data "coder_parameter" "workspace_secret" {
  name    = "workspace_secret"
  default = ""
}

module "traefik" {
  count  = 1
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain           = var.base_domain
  exposed_port     = "8080"
  preview_mode     = data.coder_parameter.preview_mode.value
  workspace_secret = data.coder_parameter.workspace_secret.value
}

# In main.tf docker_container:
# dynamic "labels" {
#   for_each = try(module.traefik[0].traefik_labels, {})
#   content { label = labels.key; value = labels.value }
# }

# In agent startup_script:
# try(module.traefik[0].auth_setup_script, "")
```

#### `preview-link-module` (DEPRECATED)
**Status**: Use `traefik-routing-module` instead.

#### `workspace-auth-module` (DEPRECATED)
**Status**: Use `traefik-routing-module` instead.

#### `password-protection-module` (DEPRECATED)
**Status**: Use `traefik-routing-module` instead.

### Server & Access Modules

#### `setup-server-module`
**Purpose**: Development server startup/management.

**Inputs**:
- `workspace_id` - Workspace ID
- `agent_id` - Agent ID
- `exposed_ports_list` - List of ports
- `default_server_command` - Command to run
- `server_name` - Display name
- `server_log_file` - Log path
- `server_pid_file` - PID path
- `server_stop_command` - Stop command
- `server_restart_command` - Restart command
- `pre_server_setup` - Setup script
- `workspace_name` - Workspace name
- `host_ip` - Host IP
- `auto_generate_html` - Generate landing page
- `startup_command` - Startup command

**Outputs**:
- `docker_ports` - Port mappings
- `setup_server_script` - Server setup script

**Usage**:
```hcl
data "coder_parameter" "startup_command" {
  name    = "startup_command"
  default = "npx http-server -p 8080"
}

module "setup_server" {
  count  = 1
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server-module?ref=PLACEHOLDER"
  
  workspace_id           = data.coder_workspace.me.id
  agent_id               = module.agent.agent_id
  exposed_ports_list     = ["8080"]
  default_server_command = data.coder_parameter.startup_command.value
  server_name            = "Dev Server"
  # ... other inputs
}
```

#### `ssh-module`
**Purpose**: SSH server configuration.

**Inputs**:
- `workspace_id` - Workspace ID
- `enable_ssh` - Enable SSH
- `ssh_port_mode` - "auto" or "manual"
- `ssh_auto_port` - Port number (0 = random)
- `ssh_password` - SSH password
- `host_ip` - Host IP

**Outputs**:
- `ssh_port` - Assigned SSH port
- `docker_ports` - Port mapping
- `ssh_copy_script` - SSH key copy script
- `ssh_setup_script` - SSH server setup script

**Usage**:
```hcl
data "coder_parameter" "ssh_enable" {
  name    = "ssh_enable"
  default = "true"
}

module "ssh" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/ssh-module?ref=PLACEHOLDER"
  
  workspace_id  = data.coder_workspace.me.id
  enable_ssh    = data.coder_parameter.ssh_enable.value
  ssh_port_mode = "auto"
  ssh_auto_port = 0
  ssh_password  = ""
  host_ip       = var.host_ip
}

# In main.tf docker_container:
# dynamic "ports" {
#   for_each = module.ssh.docker_ports != null ? [module.ssh.docker_ports] : []
#   content { internal = ports.value.internal; external = ports.value.external; protocol = "tcp" }
# }
```

### Node.js Specific Modules

#### `node-tooling-module`
**Purpose**: Node.js, npm/pnpm/yarn installation.

**Inputs**:
- `node_version` - Node version
- `package_manager` - "npm", "pnpm", or "yarn"
- `install_typescript` - Install TypeScript
- `install_eslint` - Install ESLint

**Outputs**:
- `tooling_install_script` - Installation script

#### `node-version-module`
**Purpose**: Node version selection.

**Inputs**:
- `node_version` - Version string

**Outputs**:
- `version_script` - Version setup script

#### `node-modules-persistence-module`
**Purpose**: node_modules volume persistence.

**Inputs**:
- `agent_id` - Agent ID
- `node_modules_paths` - Paths to persist

**Outputs**:
- `init_script` - Persistence setup script

### Module Dependency Guidelines

**Load Order** (recommended):
1. Core: init_shell, git_identity
2. Infrastructure: docker (if enabled)
3. Version Control: git_integration, github_cli, gitea_cli
4. Language-Specific: node_tooling, node_modules_persistence
5. Services: ssh, traefik, setup_server
6. UI: code_server, metadata

**Dependencies**:
- `code_server` requires `agent`
- `traefik` requires `agent`
- `setup_server` requires `agent`
- `ssh` requires `agent` (for metadata)
- All modules' scripts should be added to `agent.startup_script`

**Circular Dependency Warnings**:
- ⚠️ Agent needs traefik auth script, traefik needs agent_id
- Solution: Use `try()` wrapper or locals for auth script

## 7. Troubleshooting & Known Issues

### Common Problems

#### Preview Button Not Working
**Symptoms**: Preview button appears but doesn't work, or shows wrong URL.

**Causes**:
1. Traefik not configured on host
2. Wrong domain in `base_domain` variable
3. Server not actually running on exposed port
4. Firewall blocking access

**Solutions**:
1. Verify Traefik is running: `docker ps | grep traefik`
2. Check BASE_DOMAIN in `.env` file
3. Test server locally: `curl localhost:8080` inside workspace
4. Check Traefik logs: `docker logs traefik`

#### Duplicate Preview Buttons
**Symptoms**: Multiple preview buttons with same/different URLs.

**Causes**:
1. Using both `traefik-routing-module` and `preview-link-module`
2. Hardcoded `coder_app` resources in main.tf
3. Module loaded with `count` > 1

**Solutions**:
1. Use ONLY `traefik-routing-module` for preview
2. Remove hardcoded `coder_app` resources
3. Check module count: `count = 1` not `count = var.start_count`

#### Server Not Starting
**Symptoms**: Workspace starts but server not running, preview shows error.

**Causes**:
1. `setup-server-module` not included in startup script
2. Wrong command in `startup_command` parameter
3. Missing dependencies (Node.js, npm, etc.)
4. Port already in use

**Solutions**:
1. Add to agent startup: `try(module.setup_server[0].setup_server_script, "")`
2. Test command manually in terminal
3. Ensure language-specific modules load before server
4. Check process list: `ps aux | grep http-server`

#### UI Flickering During Updates
**Symptoms**: Parameters toggle, disappear, or reset during workspace updates.

**Causes**:
1. Conditional module loading with `count` based on parameters
2. Ternary operators in `startup_script` join
3. Mutable parameters that affect infrastructure
4. Unused parameters causing re-evaluation

**Solutions**:
1. Always load modules (use conditional logic inside module)
2. Extract ternaries to locals before startup_script
3. Use `mutable = false` for infrastructure parameters
4. Remove unused parameters from data blocks

#### Git Clone Not Working
**Symptoms**: Repository not cloned, workspace folder empty.

**Causes**:
1. Invalid repository URL
2. Missing git credentials
3. `git-integration-module` not in startup script
4. Script runs before git identity setup

**Solutions**:
1. Test URL: `git clone <url>` manually
2. Setup SSH keys or use HTTPS with token
3. Add to startup: `module.git_integration.clone_script`
4. Ensure order: git_identity → git_integration in startup_script

#### Authentication Not Working
**Symptoms**: Traefik auth prompt doesn't appear or fails.

**Causes**:
1. `workspace_secret` parameter empty
2. Auth directory not mounted
3. htpasswd file not created
4. Wrong username in auth file

**Solutions**:
1. Set `workspace_secret` parameter value
2. Mount traefik-auth directory in docker_container volumes
3. Check auth setup in startup logs
4. Verify username matches workspace owner

### Debugging Checklist

**When creating new template**:
- [ ] All required files present (main.tf, variables.tf, agent-params.tf)
- [ ] Module sources use `?ref=PLACEHOLDER`
- [ ] Agent startup_script includes all module scripts
- [ ] Docker container has required volumes
- [ ] base_domain and host_ip variables defined
- [ ] No circular dependencies between modules

**When adding modules**:
- [ ] Module called correctly with required inputs
- [ ] Module outputs used (not just defined)
- [ ] Module script added to agent startup_script
- [ ] Docker container updated if module needs ports/volumes/labels
- [ ] Parameters tested incrementally (one at a time)

**When pushing template**:
- [ ] .env file has correct BASE_DOMAIN and HOST_IP
- [ ] Git ref detected correctly (check dry-run output)
- [ ] Template copies to temp directory successfully
- [ ] Substitutions applied (check temp directory)
- [ ] Coder accepts push (version increments)

**When testing workspace**:
- [ ] Workspace starts without errors
- [ ] Agent connects successfully
- [ ] Startup script completes (check logs)
- [ ] All expected buttons appear in UI
- [ ] Preview button works (if configured)
- [ ] SSH access works (if enabled)
- [ ] Files/directories created as expected

### Log Locations

**Workspace Startup Logs**:
- Coder UI: Workspace → Startup Logs tab
- Terminal: Run `coder agent logs` inside workspace

**Server Logs**:
- Default location: `/tmp/server.log` (if using setup-server-module)
- Check with: `tail -f /tmp/server.log`

**Traefik Logs**:
- Host: `docker logs traefik`
- Access logs: Check Traefik config for path

**SSH Debug**:
- Test connection: `ssh -v coder@<host_ip> -p <ssh_port>`
- Server logs: `sudo tail -f /var/log/auth.log`

### Getting Help

**Information to Provide**:
1. Template name and version
2. Git branch/ref used for push
3. Coder workspace startup logs
4. Error messages (exact text)
5. Relevant module configurations
6. Expected vs actual behavior

**Quick Diagnostics**:
```bash
# Check what ref was used
./push-template-versioned.sh --dry-run my-template

# Verify module sources
grep "ref=" my-template/*.tf

# Check version
cat config/coder/scripts/.template_versions.json

# Test Coder connection
coder templates list

# View template source
coder templates show my-template
```
