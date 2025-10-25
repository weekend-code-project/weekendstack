# Setup Server Module

Prepares the workspace for serving content by setting up PORT environment variable and optionally auto-generating a default index.html file with a Python HTTP server.

## Features

- Sets `PORT` and `PORTS` environment variables
- Auto-generates a styled welcome page (optional)
- Starts Python HTTP server on the first exposed port
- Supports custom startup commands (e.g., `npm run dev`)
- **Creates preview app button** with subdomain access and health checks

## Parameters

These parameters should be declared in your template root:

```hcl
# Parameter: Auto-generate HTML
data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Serve Static Site"
  description  = "Toggle on to scaffold a static welcome page and run the static site server. Turn off to customize your server ports and startup command."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 20
}

# Parameter: Expose custom ports (only when running your own server)
data "coder_parameter" "exposed_ports" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "exposed_ports"
  display_name = "Exposed Ports"
  description  = "Add one or more ports to expose when running your own server. The first port is routed through Traefik."
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["8080"])
  mutable      = true
  order        = 21
}

# Parameter: Startup Command
data "coder_parameter" "startup_command" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run at workspace startup (for example: npm run dev)."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
}
```

## Usage

```hcl
# Call the agent module first
module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.0"
  
  startup_script = join("\n", [
    # ... other scripts
    module.setup_server.setup_server_script,
  ])
  
  # ... other agent config
}

# Call setup_server module after agent (needs agent_id for preview app)
module "setup_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.0"
  
  workspace_name        = data.coder_workspace.me.name
  workspace_owner       = data.coder_workspace_owner.me.name
  auto_generate_html    = data.coder_parameter.auto_generate_html.value
  exposed_ports_list    = local.exposed_ports_list
  startup_command       = try(data.coder_parameter.startup_command[0].value, "")
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
}
```

## Dependencies

Requires `local.exposed_ports_list` to be defined (typically from traefik-routing module).

## Outputs

- `setup_server_script` - Bash script to set up the server

## Resources Created

- `coder_app.preview` - Preview button with subdomain access and health checks on the first exposed port

## Notes

- Creates index.html only if it doesn't exist
- First port in `exposed_ports_list` becomes the default `PORT`
- Custom startup command runs in background
- Python HTTP server runs when auto_generate_html is true and no custom command provided
- Preview app includes health checks (5s interval, 6 threshold) for server availability
- Preview app uses subdomain mode for clean URLs
