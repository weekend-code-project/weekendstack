# Traefik Routing Module

Provides Docker labels for Traefik routing configuration with optional authentication.

## Features

- Generates Traefik Docker labels for routing
- Automatic subdomain configuration
- Optional authentication middleware
- Support for custom domain configuration

## Variables

- `workspace_name` - Name of the workspace
- `workspace_owner` - Owner username
- `workspace_id` - Workspace ID
- `workspace_owner_id` - Owner ID
- `make_public` - Whether workspace is public (no auth)
- `exposed_ports_list` - List of exposed ports
- `domain` - Domain for workspace URL (default: "weekendcodeproject.dev")

## Outputs

- `traefik_labels` - Map of Docker labels for Traefik
- `workspace_url` - External workspace URL (e.g., https://workspace-name.domain)

## Usage

```hcl
module "traefik_routing" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/traefik-routing?ref=v0.1.0"
  
  workspace_name     = data.coder_workspace.me.name
  workspace_owner    = data.coder_workspace_owner.me.name
  workspace_id       = data.coder_workspace.me.id
  workspace_owner_id = data.coder_workspace_owner.me.id
  make_public        = data.coder_parameter.make_public.value
  exposed_ports_list = local.exposed_ports_list
}

# Use labels in docker_container
dynamic "labels" {
  for_each = module.traefik_routing.traefik_labels
  content {
    label = labels.key
    value = labels.value
  }
}
```

## Notes

- First port in `exposed_ports_list` is used as the backend
- Workspace name is automatically lowercased for URL
- Authentication labels only added when `make_public = false`
