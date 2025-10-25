# Docker Workspace Module (POC)

This is a proof-of-concept Terraform module that demonstrates creating a proper, reusable module for Coder workspaces.

## Purpose

Test whether Coder templates can reference external modules using Terraform's `module` block with local paths.

## What This Module Does

- Creates a Coder agent with basic startup script
- Provisions a Docker container with resource limits
- Creates a persistent home volume
- Sets up Git identity
- Includes basic resource monitoring (CPU, RAM, disk)

## Usage

```hcl
module "workspace" {
  source = "../test-modules/docker-workspace"
  
  workspace_name     = data.coder_workspace.me.name
  workspace_owner    = data.coder_workspace_owner.me.name
  workspace_owner_id = data.coder_workspace_owner.me.id
  workspace_id       = data.coder_workspace.me.id
  workspace_state    = data.coder_workspace.me.transition
  
  docker_image    = "codercom/enterprise-base:ubuntu"
  container_cpu   = 2048
  container_memory = 4096
  
  agent_arch       = data.coder_provisioner.me.arch
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
}
```

## Differences from Current Setup

### Current Setup (modules/*.tf)
- Flat `.tf` files that get copied/bundled into template root
- No explicit inputs/outputs
- Uses `locals` for composition
- Files are merged at push time

### This Module
- Proper Terraform module with defined interface
- Explicit `variables.tf` for inputs
- Explicit `outputs.tf` for exports
- Referenced via `module` block
- No bundling required (Terraform resolves path)

## Testing

```bash
cd /mnt/workspace/wcp-coder/config/coder/templates/test-module-template
coder templates push test-poc --directory .
```

## Next Steps If POC Succeeds

1. Refactor existing `modules/*.tf` into proper modules
2. Organize by domain (e.g., `modules/git/`, `modules/docker/`, `modules/traefik/`)
3. Update `modular-docker` template to use module references
4. Remove bundling logic from push script
