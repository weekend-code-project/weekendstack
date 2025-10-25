# Preview Link Module

Creates a Coder app that provides a clickable external link to the workspace's Traefik URL or a custom URL.

## Features

- Auto-generated Traefik URL link (default)
- Optional custom URL with validation
- External link that opens in browser
- Appears as "External URL" button in Coder UI

## Parameters

These parameters should be declared in your template root:

```hcl
# Toggle: Use Custom URL
data "coder_parameter" "use_custom_preview_url" {
  name         = "use_custom_preview_url"
  display_name = "Custom Preview URL"
  description  = "Use a custom URL for the preview link instead of the auto-generated Traefik URL."
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 30
}

# Custom Preview URL (only shown when custom URL is enabled)
data "coder_parameter" "custom_preview_url" {
  count        = data.coder_parameter.use_custom_preview_url.value ? 1 : 0
  
  name         = "custom_preview_url"
  display_name = "Custom URL"
  description  = "Custom URL for the external preview link"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 31
  
  validation {
    regex = "^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$"
    error = "Must be a valid URL starting with http:// or https://"
  }
}
```

## Usage

```hcl
# Requires traefik-routing module for workspace_url
module "traefik_routing" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/traefik-routing?ref=v0.1.0"
  # ... traefik config
}

# Call preview-link module
module "preview_link" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/preview-link?ref=v0.1.0"
  
  agent_id              = module.agent.agent_id
  workspace_url         = module.traefik_routing.workspace_url
  workspace_start_count = data.coder_workspace.me.start_count
  use_custom_url        = data.coder_parameter.use_custom_preview_url.value
  custom_url            = try(data.coder_parameter.custom_preview_url[0].value, "")
}
```

## Outputs

This module creates a `coder_app.preview_link` resource but doesn't export any outputs.

## Notes

- Default behavior: Links to auto-generated Traefik URL (e.g., `https://workspace-name.weekendcodeproject.dev`)
- Custom URL mode: User can specify any valid HTTP/HTTPS URL
- URL validation ensures proper format with protocol
- External link opens in new browser tab
- Icon: Desktop icon (`/icon/desktop.svg`)
