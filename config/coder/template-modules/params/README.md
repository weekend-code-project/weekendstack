# Shared Parameter Modules

These parameter files provide reusable configurations for common workspace features. They are automatically overlaid into templates during the push process via `scripts/push-template-versioned.sh`.

## Overlay Precedence Rules

The push script follows these precedence rules when building a template:

1. **Template-local file WINS**: If `templates/my-template/foo-params.tf` exists, it is used as-is
2. **Shared file as fallback**: If the template has no `foo-params.tf`, the shared version from `template-modules/params/foo-params.tf` is copied in
3. **Explicit prevention**: Create an empty/minimal placeholder file to prevent a shared param from being overlaid

### Example: Preventing Overlay

To prevent a shared param file from being overlaid (e.g., for testing), create a minimal placeholder:

```hcl
# templates/my-template/ssh-params.tf
# =============================================================================
# Phase 0: NO SSH PARAMS
# =============================================================================
# This file prevents overlay of shared ssh-params.tf

# Placeholder to prevent shared file overlay
```

## Available Shared Param Files

- `agent-params.tf` - Coder agent configuration
- `docker-params.tf` - Docker-in-Docker functionality
- `git-params.tf` - Git identity and integration
- `metadata-params.tf` - Workspace resource monitoring
- `setup-server-params.tf` - Development server configuration
- `ssh-params.tf` - SSH server access
- `traefik-params.tf` - Traefik routing and authentication

## Creating Template Overrides

When a template needs custom behavior:

1. Copy the shared param file to your template directory
2. Modify as needed for that template's requirements
3. Add an `# OVERRIDE NOTE:` comment explaining why
4. The template-local version will be used instead of the shared version

### Example: Template Override

```hcl
# templates/vite-template/setup-server-params.tf
# =============================================================================
# Setup Server Parameters (Vite Template Override)
# =============================================================================
# OVERRIDE NOTE: This file overrides the shared setup-server-params.tf
# to provide a Vite-specific default startup command.

data "coder_parameter" "startup_command" {
  name    = "startup_command"
  default = "npx vite --host 0.0.0.0 --port 8080"  # Vite-specific default
  ...
}
```

## Module Reference Pattern

All module sources should use the `PLACEHOLDER` pattern for git refs:

```hcl
module "example" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/example-module?ref=PLACEHOLDER"
}
```

The push script automatically replaces `PLACEHOLDER` with the current git ref (branch, tag, or commit).
