# Preview Link Module

Creates Coder app buttons for accessing the workspace via different preview modes.

## Features

- **Internal Mode**: Coder's built-in proxy (localhost through Coder UI)
- **Traefik Mode**: External subdomain routing (workspace-name.domain.com)
- **Custom Mode**: User-specified URL with validation
- Automatic URL generation based on workspace name
- Health checks for internal mode
- Decoupled from server setup logic

## Preview Modes

### Internal (Coder Proxy)
- Routes through Coder's proxy at `https://coder.domain.com/@owner/workspace.main/apps/preview`
- Uses localhost connection inside workspace
- Includes health checks (5s interval, 6 threshold)
- Best for: Private development, authentication required

### Traefik (External Subdomain)
- Direct external access via `https://workspace-name.domain.com`
- Requires Traefik routing to be configured
- Opens in new browser tab
- Best for: Public demos, sharing with team

### Custom URL
- User-specified URL (e.g., `https://myapp.example.com`)
- Validated format (must start with http:// or https://)
- Opens in new browser tab
- Best for: Custom domains, alternative routing

## Parameters

These parameters should be declared in your template root:

```hcl
# Parameter: Preview Link Mode
data "coder_parameter" "preview_link_mode" {
  name         = "preview_link_mode"
  display_name = "Preview Link Mode"
  description  = "Choose how the preview app URL is generated."
  type         = "string"
  default      = "traefik"
  mutable      = true
  order        = 23
  
  option {
    name  = "Internal (Coder Proxy)"
    value = "internal"
    icon  = "/icon/coder.svg"
  }
  option {
    name  = "Traefik (External Subdomain)"
    value = "traefik"
    icon  = "/icon/globe.svg"
  }
  option {
    name  = "Custom URL"
    value = "custom"
    icon  = "/icon/link.svg"
  }
}

# Parameter: Custom Preview URL (conditional)
data "coder_parameter" "custom_preview_url" {
  count        = data.coder_parameter.preview_link_mode.value == "custom" ? 1 : 0
  
  name         = "custom_preview_url"
  display_name = "Custom Preview URL"
  description  = "Enter your custom preview URL (e.g., https://myapp.example.com)"
  type         = "string"
  default      = ""
  mutable      = true
  form_type    = "input"
  order        = 24
  
  validation {
    regex = "^https?://.+"
    error = "URL must start with http:// or https://"
  }
}
```

## Usage

```hcl
# Call preview_link module
module "preview_link" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/preview-link?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  base_domain           = "weekendcodeproject.dev"  # Can be parameterized
  exposed_port          = element(local.exposed_ports_list, 0)
  workspace_start_count = data.coder_workspace.me.start_count
  preview_mode          = data.coder_parameter.preview_link_mode.value
  custom_preview_url    = try(data.coder_parameter.custom_preview_url[0].value, "")
}
```

## Outputs

- `preview_url` - The resolved preview URL based on selected mode
- `traefik_url` - The generated Traefik external URL (always available)

## Resources Created

Conditionally creates ONE of:
- `coder_app.preview` - Internal proxy mode
- `coder_app.preview_traefik` - Traefik external mode
- `coder_app.preview_custom` - Custom URL mode

## Example URLs

Given workspace `docker-test-1` owned by `jessefreeman`:

- **Internal**: `https://coder.weekendcodeproject.dev/@jessefreeman/docker-test-1.main/apps/preview`
- **Traefik**: `https://docker-test-1.weekendcodeproject.dev`
- **Custom**: Whatever the user enters (e.g., `https://myapp.com`)

## Notes

- Only one preview button is created at a time based on `preview_mode`
- Base domain defaults to `weekendcodeproject.dev` but can be parameterized
- Internal mode includes health checks, external modes do not
- Traefik mode requires proper Docker labels (handled by traefik-routing module)