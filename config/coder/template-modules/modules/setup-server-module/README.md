# Setup Server Module# Setup Server Module



A reusable Terraform module for setting up development servers in Coder workspaces. This module handles:Prepares the workspace for serving content by setting up PORT environment variable and optionally auto-generating a default index.html file with a Python HTTP server.



- Port configuration and environment variable setup**NOTE:** This module only handles server setup. For preview link buttons in the Coder UI, use the separate `preview-link` module.

- Optional auto-generation of a static HTML welcome page

- Custom startup command support## Features

- Template-specific server implementations (Python, Node.js, etc.)

- Pre-server setup scripts (dependency installation, initialization)- Sets `PORT` and `PORTS` environment variables

- Auto-generates a styled welcome page (optional)

## Features- Starts Python HTTP server on the first exposed port

- Supports custom startup commands (e.g., `npm run dev`)

- **Universal Server Setup**: Works with any server type by accepting template-specific commands- Decoupled from preview link logic

- **Static Site Toggle**: Optionally generates a branded welcome page with getting-started instructions

- **Custom Commands**: Users can override the default server with their own startup command## Parameters

- **Parameterized HTML**: Template-specific instructions and branding in the welcome page

- **Pre-Setup Hooks**: Run initialization scripts before starting the server (e.g., `npm init`, package installation)These parameters should be declared in your template root:



## Usage```hcl

# Parameter: Auto-generate HTML

### Python Template Exampledata "coder_parameter" "auto_generate_html" {

  name         = "auto_generate_html"

```hcl  display_name = "Serve Static Site"

module "setup_server" {  description  = "Toggle on to scaffold a static welcome page and run the static site server. Turn off to customize your server ports and startup command."

  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server?ref=PLACEHOLDER"  type         = "bool"

    form_type    = "switch"

  # Port configuration  default      = true

  exposed_ports_list = local.exposed_ports_list  mutable      = true

    order        = 20

  # Python-specific configuration}

  default_server_command = "python3 -m http.server $PORT --bind 0.0.0.0"

  server_name           = "Python 3 HTTP Server"# Parameter: Expose custom ports (only when running your own server)

  server_log_file       = "/tmp/http-server.log"data "coder_parameter" "exposed_ports" {

  server_pid_file       = "/tmp/http-server.pid"  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1

    name         = "exposed_ports"

  # HTML content  display_name = "Exposed Ports"

  html_status_message = "Python HTTP server is running!"  description  = "Add one or more ports to expose when running your own server. The first port is routed through Traefik."

  html_server_info    = "Python 3 HTTP server on port $PORT"  type         = "list(string)"

  html_instructions   = <<-INSTRUCTIONS  form_type    = "tag-select"

    # Edit the current page  default      = jsonencode(["8080"])

    vi index.html  mutable      = true

      order        = 21

    # Or create your own site}

    mkdir -p mysite

    cd mysite# Parameter: Startup Command

    echo "<h1>Hello World</h1>" > index.htmldata "coder_parameter" "startup_command" {

      count        = data.coder_parameter.auto_generate_html.value ? 0 : 1

    # Restart the server  name         = "startup_command"

    pkill -f "python3 -m http.server"  display_name = "Startup Command"

    python3 -m http.server $PORT  description  = "Command to run at workspace startup (for example: npm run dev)."

  INSTRUCTIONS  type         = "string"

    default      = ""

  # Workspace metadata  mutable      = true

  workspace_name  = data.coder_workspace.me.name  order        = 22

  workspace_owner = data.coder_workspace_owner.me.name}

  ```

  # Parameters

  auto_generate_html = data.coder_parameter.auto_generate_html.value## Usage

  startup_command    = local.startup_cmd_value

}```hcl

# Call setup_server module (does not need agent_id)

# Use the output in agent startup scriptmodule "setup_server" {

locals {  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server?ref=PLACEHOLDER"

  setup_server_script = module.setup_server.setup_server_script  

}  workspace_name     = data.coder_workspace.me.name

```  workspace_owner    = data.coder_workspace_owner.me.name

  auto_generate_html = data.coder_parameter.auto_generate_html.value

### Node.js Template Example  exposed_ports_list = local.exposed_ports_list

  startup_command    = try(data.coder_parameter.startup_command[0].value, "")

```hcl}

module "setup_server" {

  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/setup-server?ref=PLACEHOLDER"# Add to agent startup script

  module "agent" {

  exposed_ports_list = local.exposed_ports_list  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent?ref=PLACEHOLDER"

    

  # Node-specific configuration  startup_script = join("\n", [

  default_server_command = "npm run start"    # ... other scripts

  server_name           = "Express Server"    module.setup_server.setup_server_script,

  server_log_file       = "/tmp/express-server.log"  ])

  server_pid_file       = "/tmp/express-server.pid"  

    # ... other agent config

  html_status_message = "Express server is running!"}

  html_server_info    = "Node.js Express server on port $PORT"```

  html_instructions   = <<-INSTRUCTIONS

    # Create a new Vite app## Dependencies

    npm create vite@latest myapp

    cd myappRequires `local.exposed_ports_list` to be defined (typically from traefik-routing module).

    npm install

    npm run dev -- --port $PORT## Outputs

    

    # Or run your custom app- `setup_server_script` - Bash script to set up the server

    npm start

  INSTRUCTIONS## Notes

  

  # Pre-setup: Initialize package.json and install Express- Creates index.html only if it doesn't exist

  pre_server_setup = <<-SETUP- First port in `exposed_ports_list` becomes the default `PORT`

    if [ ! -f package.json ]; then npm init -y >/dev/null 2>&1 || true; fi- No preview buttons created - use `preview-link` module for that

    if ! npm list express >/dev/null 2>&1; then- Custom startup command runs in background

      echo "[SETUP-SERVER] Installing express..."- Python HTTP server runs when auto_generate_html is true and no custom command provided

      npm install express >/dev/null 2>&1 || true- Preview app includes health checks (5s interval, 6 threshold) for server availability

    fi- Preview app uses subdomain mode for clean URLs

    # Create simple Express server
    cat > server.js <<'JS'
    const express = require('express');
    const fs = require('fs');
    const path = require('path');
    const port = process.env.PORT || 8080;
    const app = express();
    app.get('/', (req,res) => {
      const p = path.join(process.cwd(),'index.html');
      if (fs.existsSync(p)) res.type('html').send(fs.readFileSync(p));
      else res.status(404).send('index.html not found');
    });
    app.listen(port, '0.0.0.0', () => console.log('[Express] listening on http://localhost:' + port));
    JS
    # Add start script to package.json
    node -e "const fs=require('fs');const p='package.json';const pkg=fs.existsSync(p)?JSON.parse(fs.readFileSync(p)):{};pkg.scripts=pkg.scripts||{};pkg.scripts.start=pkg.scripts.start||'node server.js';fs.writeFileSync(p, JSON.stringify(pkg, null, 2));"
  SETUP
  
  workspace_name     = data.coder_workspace.me.name
  workspace_owner    = data.coder_workspace_owner.me.name
  auto_generate_html = data.coder_parameter.auto_generate_html.value
  startup_command    = local.startup_cmd_value
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `exposed_ports_list` | List of ports to expose | `list(string)` | n/a | yes |
| `default_server_command` | Default command to start the server | `string` | n/a | yes |
| `server_name` | Display name of the server | `string` | n/a | yes |
| `server_log_file` | Path to server log file | `string` | `/tmp/server.log` | no |
| `server_pid_file` | Path to server PID file | `string` | `/tmp/server.pid` | no |
| `html_status_message` | Status message in generated HTML | `string` | `"Server is running!"` | no |
| `html_server_info` | Server info in generated HTML | `string` | `"Server running on port $PORT"` | no |
| `html_instructions` | Getting started instructions | `string` | `""` | no |
| `pre_server_setup` | Script to run before starting server | `string` | `""` | no |
| `workspace_name` | Workspace name | `string` | n/a | yes |
| `workspace_owner` | Workspace owner | `string` | n/a | yes |
| `auto_generate_html` | Whether to auto-generate index.html | `string` | n/a | yes |
| `startup_command` | Custom startup command | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| `setup_server_script` | Bash script to set up and start the server |

## How It Works

1. **Port Setup**: Exports `PORT` and `PORTS` environment variables
2. **HTML Generation**: If `auto_generate_html` is true and `index.html` doesn't exist, creates a branded welcome page
3. **Pre-Setup**: Runs `pre_server_setup` script if provided (for dependency installation, etc.)
4. **Server Startup**: 
   - If custom `startup_command` is provided, uses that
   - Otherwise, if `auto_generate_html` is true, runs `default_server_command`
   - All processes are properly backgrounded with `nohup` and output redirection

## Benefits

- **DRY**: Server setup logic is defined once, used across all templates
- **Flexibility**: Templates provide only what's unique (command, instructions, pre-setup)
- **Consistency**: All templates get the same robust server startup behavior
- **Maintainability**: Bug fixes and improvements benefit all templates
- **Extensibility**: Easy to add new template types (Go, Rust, etc.)
