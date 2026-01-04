# Traefik Authentication Module

Configures Traefik basic authentication for workspace access using htpasswd.

## Features

- Generates htpasswd file for authentication
- Creates Traefik middleware configuration
- Conditional authentication based on public/private toggle
- Automatic cleanup when switching to public mode

## Variables

- `workspace_name` - Name of the workspace
- `workspace_owner` - Owner username
- `make_public` - Whether workspace is public (no auth)
- `workspace_secret` - Password for authentication (sensitive)

## Outputs

- `traefik_auth_enabled` - Boolean indicating if auth is enabled
- `traefik_auth_setup_script` - Bash script for setting up authentication

## Usage

```hcl
module "traefik_auth" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/traefik-auth?ref=PLACEHOLDER"
  
  workspace_name   = data.coder_workspace.me.name
  workspace_owner  = data.coder_workspace_owner.me.name
  make_public      = data.coder_parameter.make_public.value
  workspace_secret = random_password.workspace_secret.result
}
```

## Requirements

- `/traefik-auth` directory must be mounted in container
- `apache2-utils` package (installed automatically by script)
- Traefik must watch `/traefik-auth` for dynamic configuration
