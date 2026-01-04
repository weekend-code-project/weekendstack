# Traefik Routing Module

Unified module that provides Traefik routing labels and preview buttons for workspace access.

## Features

- **Dual Preview Modes**:
  - `internal`: Coder's built-in proxy (localhost through Coder UI)
  - `traefik`: External HTTPS subdomain routing (workspace-name.domain.com)

- **Optional Authentication**: Password-protect Traefik routes with basic auth

- **Dynamic Labels**: Generates Docker labels for Traefik routing configuration

- **Preview Buttons**: Creates Coder app buttons in the workspace UI

## Usage

```hcl
module "traefik" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-routing?ref=v0.3.0"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  workspace_id          = data.coder_workspace.me.id
  workspace_owner_id    = data.coder_workspace_owner.me.id
  workspace_start_count = data.coder_workspace.me.start_count
  
  domain       = var.base_domain
  exposed_port = "8080"
  preview_mode = "traefik"  # or "internal"
  
  make_public      = true   # Set to false to require password
  workspace_secret = ""     # Required when make_public = false
}

# Apply labels to Docker container
resource "docker_container" "workspace" {
  # ... other config ...
  
  dynamic "labels" {
    for_each = module.traefik.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `agent_id` | Coder agent ID for preview buttons | `string` | - | yes |
| `workspace_name` | Name of the workspace | `string` | - | yes |
| `workspace_owner` | Owner username | `string` | - | yes |
| `workspace_id` | Workspace ID | `string` | - | yes |
| `workspace_owner_id` | Owner ID | `string` | - | yes |
| `workspace_start_count` | Workspace start count | `number` | - | yes |
| `domain` | Base domain for Traefik routing | `string` | - | yes |
| `exposed_port` | Primary exposed port | `string` | `"8080"` | no |
| `preview_mode` | Preview mode (`internal` or `traefik`) | `string` | `"traefik"` | no |
| `make_public` | Whether workspace is public (no auth) | `bool` | `true` | no |
| `workspace_secret` | Password for workspace auth | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| `traefik_labels` | Map of Traefik Docker labels |
| `workspace_url` | External workspace URL (HTTPS subdomain) |
| `preview_url` | Active preview URL based on mode |
| `auth_setup_script` | Script to set up Traefik auth (empty if public) |
| `auth_enabled` | Whether authentication is enabled |

## Authentication Setup

When `make_public = false`, the module generates a setup script that:

1. Installs `htpasswd` (apache2-utils)
2. Creates hashed password file in `/traefik-auth/hashed_password-{workspace}`
3. Generates dynamic Traefik middleware config in `/traefik-auth/dynamic-{workspace}.yaml`

The `/traefik-auth` directory must be mounted from the host for auth to work.

## Preview Modes

### Internal Mode
- Uses Coder's built-in proxy
- URL: `http://localhost:{port}` (proxied through Coder UI)
- Icon: Coder logo
- No Traefik labels generated

### Traefik Mode
- External HTTPS subdomain routing
- URL: `https://{workspace}.{domain}`
- Icon: Globe (public) or Lock (protected)
- Generates Traefik Docker labels for routing

## Migration Notes

This module replaces and merges:
- `routing-labels-test` module (Traefik labels)
- `preview-link` module (preview buttons)

Custom preview URLs are not supported in this refactored version.
