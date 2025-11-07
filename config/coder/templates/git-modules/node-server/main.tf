terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# MODULE: Node Default Server Bootstrap
# =============================================================================
# DESCRIPTION:
#   Scaffolds a minimal Node project if none exists and starts a simple server.

variable "workspace_start_count" {
  type        = number
  description = "Used to conditionally create app on first start"
}

variable "agent_id" {
  type        = string
}

variable "exposed_ports" {
  type        = list(string)
  default     = ["3000"]
}

variable "server_mode" {
  description = "Server mode: default|static|custom"
  type        = string
  default     = "default"
}

variable "startup_command" {
  description = "Custom startup command when server_mode=custom"
  type        = string
  default     = ""
}

output "server_ports" {
  value = var.exposed_ports
}

resource "coder_app" "preview" {
  count        = var.workspace_start_count
  agent_id     = var.agent_id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/icon/code.svg"
  url          = "http://localhost:${element(var.exposed_ports, 0)}"
  subdomain    = false
  share        = "owner"
}

locals {
  node_server_script = <<-EOT
    #!/bin/bash
    set -e
    echo "[NODE-SERVER] Bootstrapping default Node app if needed..."
    cd /home/coder/workspace
    export PORT=${element(var.exposed_ports, 0)}
    MODE="${var.server_mode}"
    echo "[NODE-SERVER] Mode: $MODE | PORT=$PORT"

    case "$MODE" in
      custom)
        START_CMD="${var.startup_command}"
        if [ -z "$START_CMD" ]; then
          echo "[NODE-SERVER] No startup_command provided for custom mode; skipping"
        else
          echo "[NODE-SERVER] Running custom command: $START_CMD"
          eval "$START_CMD" &
        fi
        ;;
      static)
        if [ ! -f package.json ]; then
          echo "[NODE-SERVER] Initializing package.json"
          npm init -y >/dev/null 2>&1 || true
        fi
        if [ ! -f index.html ]; then
          echo "[NODE-SERVER] Creating default index.html"
          cat > index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Node Workspace</title>
  <style>body{font-family:system-ui,Arial,sans-serif;max-width:800px;margin:40px auto;padding:20px;line-height:1.6}</style>
</head>
<body>
  <h1>Welcome to your Node Workspace</h1>
  <p>This page is served statically by a minimal Node server.</p>
  <p>Port: <span id="port"></span></p>
  <script>document.getElementById('port').textContent=(location.port||'${element(var.exposed_ports, 0)}');</script>
</body>
</html>
HTML
        fi
        cat > server.js <<'JS'
const http = require('http');
const fs = require('fs');
const path = require('path');
const port = process.env.PORT || ${element(var.exposed_ports, 0)};
const server = http.createServer((req, res) => {
  const filePath = path.join(process.cwd(), 'index.html');
  try {
    const content = fs.readFileSync(filePath);
    res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
    res.end(content);
  } catch (e) {
    res.writeHead(500, {'Content-Type': 'text/plain'});
    res.end('index.html not found');
  }
});
server.listen(port, '0.0.0.0', () => console.log('Static server running on http://localhost:' + port));
JS
        node -e "const fs=require('fs'); const pkg=JSON.parse(fs.readFileSync('package.json')); pkg.scripts=pkg.scripts||{}; pkg.scripts.start='node server.js'; fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));"
        echo "[NODE-SERVER] Starting static server on $PORT"
        npm run start --if-present &
        ;;
      default|*)
        if [ ! -f package.json ]; then
          echo "[NODE-SERVER] Initializing package.json"
          npm init -y >/dev/null 2>&1 || true
          # Simple dynamic server (no deps)
          cat > server.js <<'JS'
const http = require('http');
const port = process.env.PORT || ${element(var.exposed_ports, 0)};
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
  res.end('<h1>Welcome to your Node Workspace</h1><p>Listening on port ' + port + '</p>');
});
server.listen(port, '0.0.0.0', () => console.log('Server running on http://localhost:' + port));
JS
          node -e "const fs=require('fs'); const pkg=JSON.parse(fs.readFileSync('package.json')); pkg.scripts=pkg.scripts||{}; pkg.scripts.start='node server.js'; fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));"
          echo "[NODE-SERVER] Default server scaffolded"
        else
          echo "[NODE-SERVER] Existing package.json detected; not scaffolding"
        fi
        echo "[NODE-SERVER] Starting default server on $PORT"
        npm run start --if-present &
        ;;
    esac
    echo "[NODE-SERVER] Done."
    echo ""
  EOT
}

output "node_server_script" {
  description = "Script to scaffold and start Node server"
  value       = local.node_server_script
}
