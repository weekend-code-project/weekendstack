# =============================================================================
# Node Template - Setup Server (Local)
# =============================================================================
# Mirrors the shared setup-server module UX (auto_generate_html, exposed_ports, startup_command)
# EXACT same parameter names, defaults, ordering, and behavior — only difference:
# implementation uses Node + Express instead of Python http.server.

data "coder_parameter" "auto_generate_html" {
  name         = "auto_generate_html"
  display_name = "Serve Static Site"
  description  = "Toggle on to scaffold a static welcome page."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 20
}

data "coder_parameter" "exposed_ports" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "exposed_ports"
  display_name = "Exposed Ports"
  description  = "Ports to expose."
  type         = "list(string)"
  form_type    = "tag-select"
  default      = jsonencode(["8080"])  # Match shared module default
  mutable      = true
  order        = 21
}

data "coder_parameter" "startup_command" {
  count        = data.coder_parameter.auto_generate_html.value ? 0 : 1
  name         = "startup_command"
  display_name = "Startup Command"
  description  = "Command to run at startup."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 22
}

locals {
  exposed_ports_raw  = try(data.coder_parameter.exposed_ports[0].value, jsonencode(["8080"]))
  exposed_ports_list = try(jsondecode(local.exposed_ports_raw), tolist(local.exposed_ports_raw), [tostring(local.exposed_ports_raw)])
}

# Preview app matching the first exposed port
resource "coder_app" "preview" {
  count        = data.coder_workspace.me.start_count
  agent_id     = module.agent.agent_id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/icon/code.svg"
  url          = "http://localhost:${element(local.exposed_ports_list, 0)}"
  subdomain    = false
  share        = "owner"
  healthcheck {
    url       = "http://localhost:${element(local.exposed_ports_list, 0)}"
    interval  = 5
    threshold = 6
  }
}

# Node-based setup server script
locals {
  setup_server_script = <<-EOT
    #!/bin/bash
    set -e
    export PORTS="${join(",", local.exposed_ports_list)}"
    export PORT="${element(local.exposed_ports_list, 0)}"
    echo "[SETUP-SERVER] Configuring Node Express server..."
    echo "[SETUP-SERVER] Port: $PORT"
    cd /home/coder/workspace
    AUTO_HTML="${data.coder_parameter.auto_generate_html.value}"
    STARTUP_CMD="${try(data.coder_parameter.startup_command[0].value, "")}" 
    if [ "$AUTO_HTML" = "true" ]; then
      if [ ! -f index.html ]; then
        echo "[SETUP-SERVER] Creating default index.html..."
        cat <<HTML > index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Coder Workspace - ${data.coder_workspace.me.name}</title>
  <style>body{font-family:system-ui,-apple-system,Arial,sans-serif;max-width:800px;margin:40px auto;padding:20px;line-height:1.6;background:#111;color:#eee}a{color:#4ea1ff}code{background:#222;padding:2px 6px;border-radius:4px}</style>
</head>
<body>
  <h1>Workspace: ${data.coder_workspace.me.name}</h1>
  <p><strong>Status:</strong> Server is running.</p>
  <p><strong>Port:</strong> $PORT</p>
  <h2>Getting Started (Node)</h2>
  <pre><code>npm create vite@latest myapp
cd myapp
npm install
npm run dev -- --port $PORT</code></pre>
</body>
</html>
HTML
        echo "[SETUP-SERVER] ✓ index.html created"
      else
        echo "[SETUP-SERVER] ✓ index.html already exists"
      fi
      # Ensure package.json
      if [ ! -f package.json ]; then npm init -y >/dev/null 2>&1 || true; fi
      # Install express (only once)
      if ! npm list express >/dev/null 2>&1; then
        echo "[SETUP-SERVER] Installing express..."
        npm install express >/dev/null 2>&1 || true
      fi
      cat > server.js <<'JS'
const express = require('express');
const fs = require('fs');
const path = require('path');
const port = process.env.PORT || 8080;
const app = express();
app.get('/', (req,res) => {
  const filePath = path.join(process.cwd(),'index.html');
  if (fs.existsSync(filePath)) {
    res.type('html').send(fs.readFileSync(filePath));
  } else {
    res.status(404).send('index.html not found');
  }
});
app.listen(port, '0.0.0.0', () => console.log('[Express] listening on http://localhost:' + port));
JS
      node -e "const fs=require('fs'); const p='package.json'; const pkg=fs.existsSync(p)?JSON.parse(fs.readFileSync(p)):{}; pkg.scripts=pkg.scripts||{}; pkg.scripts.start=pkg.scripts.start||'node server.js'; fs.writeFileSync(p, JSON.stringify(pkg, null, 2));"
      echo "[SETUP-SERVER] Starting Express server on $PORT"
      npm run start --if-present &
    else
      if [ -n "$STARTUP_CMD" ]; then
        echo "[SETUP-SERVER] Running custom startup command..."
        echo "[SETUP-SERVER] Command: $STARTUP_CMD"
        eval "$STARTUP_CMD" &
      else
        echo "[SETUP-SERVER] No server configured (enable 'Serve Static Site' or provide a startup command)."
      fi
    fi
    echo ""
  EOT
}

output "setup_server_script" {
  value       = local.setup_server_script
  description = "Node-based setup server script"
}
