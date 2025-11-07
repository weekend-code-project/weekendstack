terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# Setup Server (Node/Express) Module
# =============================================================================
# Same variables/outputs/behavior as shared setup-server module, but
# the default server implementation uses Node + Express instead of Python.

variable "workspace_name" {
  description = "Name of the workspace"
  type        = string
}

variable "workspace_owner" {
  description = "Owner of the workspace"
  type        = string
}

variable "auto_generate_html" {
  description = "Whether to auto-generate default index.html"
  type        = bool
  default     = true
}

variable "exposed_ports_list" {
  description = "List of exposed ports"
  type        = list(string)
}

variable "startup_command" {
  description = "Optional startup command"
  type        = string
  default     = ""
}

variable "agent_id" {
  description = "Coder agent ID for the preview app"
  type        = string
}

variable "workspace_start_count" {
  description = "Workspace start count for conditional creation"
  type        = number
}

variable "workspace_url" {
  description = "External Traefik URL for the workspace"
  type        = string
  default     = ""
}

variable "preview_url" {
  description = "Preview URL to register in coder_app (local/traefik/custom)"
  type        = string
  default     = ""
}

# =============================================================================
# Preview App (identical to shared)
# =============================================================================

resource "coder_app" "preview" {
  count        = var.workspace_start_count
  agent_id     = var.agent_id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/icon/code.svg"
  url          = coalesce(var.preview_url, "http://localhost:${element(var.exposed_ports_list, 0)}")
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = coalesce(var.preview_url, "http://localhost:${element(var.exposed_ports_list, 0)}")
    interval  = 5
    threshold = 6
  }
}

# =============================================================================
# Setup Script (Express-based)
# =============================================================================

output "setup_server_script" {
  value = <<-EOT
    #!/bin/bash
    set -e

    export PORTS="${join(",", var.exposed_ports_list)}"
    export PORT="${element(var.exposed_ports_list, 0)}"

    echo "[SETUP-SERVER] Configuring Node Express server..."
    echo "[SETUP-SERVER] Port: $PORT"

    cd /home/coder/workspace

    AUTO_HTML="${var.auto_generate_html}"
    STARTUP_CMD="${var.startup_command}"

    # Optionally create an index.html (identical UX to shared module)
    if [ "$AUTO_HTML" = "true" ]; then
      if [ ! -f index.html ]; then
  echo "[SETUP-SERVER] Creating default index.html..."
  # Unquoted heredoc to expand $PORT
  cat <<HTML > index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Coder Workspace - ${var.workspace_name}</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; line-height: 1.6; background: #f5f5f5; }
        .container { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; margin-top: 0; }
        .status { background: #e8f5e9; padding: 15px; border-radius: 4px; border-left: 4px solid #4caf50; margin: 20px 0; }
        .info { background: #e3f2fd; padding: 15px; border-radius: 4px; border-left: 4px solid #2196f3; margin: 20px 0; }
        code { background: #f5f5f5; padding: 2px 6px; border-radius: 3px; font-family: 'Monaco', 'Courier New', monospace; }
        a { color: #1976d2; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; color: #666; font-size: 14px; }
    </style>
    <meta http-equiv="refresh" content="0; url=http://localhost:$PORT" />
    <meta name="coder-preview-url" content="http://localhost:$PORT" />
    <meta name="coder-workspace" content="${var.workspace_name}" />
    <meta name="coder-owner" content="${var.workspace_owner}" />
    <meta name="coder-ports" content="$PORTS" />
    <meta name="coder-port" content="$PORT" />
    <meta name="coder-url" content="${var.workspace_url}" />
    <meta name="theme-color" content="#111" />
    <meta name="description" content="Coder Express static server" />
    <link rel="icon" href="/icon/code.svg" />
    <style>body{background:#111;color:#eee}</style>
    <style>.container{background:#1b1b1b;color:#eee}</style>
    <style>a{color:#4ea1ff}</style>
    <style>code{background:#222}</style>
    <title>Workspace: ${var.workspace_name}</title>
    <meta property="og:title" content="Workspace: ${var.workspace_name}" />
    <meta property="og:description" content="Preview running on port $PORT" />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="http://localhost:$PORT" />
</head>
<body>
    <div class="container">
    <h1>Workspace: ${var.workspace_name}</h1>
    <div class="status"><strong>Status:</strong> Workspace is running!</div>
    <div class="info">
      <strong>Access URLs:</strong>
      <ul>
        <li>Local Preview: <a href="http://localhost:$PORT">http://localhost:$PORT</a></li>
      </ul>
    </div>
    <h2>Getting Started</h2>
<pre><code># Node.js
npm create vite@latest myapp
cd myapp
npm install
npm run dev -- --port $PORT

# Your custom app
npm start</code></pre>
    <h2>Workspace Info</h2>
    <ul>
      <li><strong>Owner:</strong> ${var.workspace_owner}</li>
      <li><strong>Port:</strong> $PORT</li>
    </ul>
    <div class="footer"><em>Auto-generated by Coder</em></div>
    </div>
</body>
</html>
HTML
        echo "[SETUP-SERVER] ✓ index.html created"
      else
        echo "[SETUP-SERVER] ✓ index.html already exists (leaving as-is)"
      fi
    fi

    # Helper: ensure a process isn't already running on this port
    is_port_in_use() {
      ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$PORT$" || netstat -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$PORT$"
    }

    # If custom command provided, run it; otherwise start Express for AUTO_HTML
    if [ -n "$STARTUP_CMD" ]; then
      echo "[SETUP-SERVER] Running custom startup command..."
      echo "[SETUP-SERVER] Command: $STARTUP_CMD"
      # Redirect output and fully detach to avoid keeping stdout/stderr pipes open
      nohup bash -lc "$STARTUP_CMD" > /tmp/custom-startup.log 2>&1 &
      echo $! > /tmp/custom-startup.pid
      echo "[SETUP-SERVER] ✓ Custom command started (PID: $(cat /tmp/custom-startup.pid))"
    elif [ "$AUTO_HTML" = "true" ]; then
      # Ensure package.json and install express once
      if [ ! -f package.json ]; then npm init -y >/dev/null 2>&1 || true; fi
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
  const p = path.join(process.cwd(),'index.html');
  if (fs.existsSync(p)) res.type('html').send(fs.readFileSync(p));
  else res.status(404).send('index.html not found');
});
app.listen(port, '0.0.0.0', () => console.log('[Express] listening on http://localhost:' + port));
JS
      node -e "const fs=require('fs');const p='package.json';const pkg=fs.existsSync(p)?JSON.parse(fs.readFileSync(p)):{};pkg.scripts=pkg.scripts||{};pkg.scripts.start=pkg.scripts.start||'node server.js';fs.writeFileSync(p, JSON.stringify(pkg, null, 2));"
      echo "[SETUP-SERVER] Starting Express server on $PORT"
      # Avoid duplicate listener if already active
      if is_port_in_use; then
        echo "[SETUP-SERVER] Port $PORT already in use; assuming server is running."
      else
        nohup npm run start --if-present > /tmp/express-server.log 2>&1 &
        echo $! > /tmp/express-server.pid
        echo "[SETUP-SERVER] ✓ Express started (PID: $(cat /tmp/express-server.pid))"
      fi
    else
      echo "[SETUP-SERVER] Auto HTML disabled and no startup command provided; not starting a server."
    fi

    echo ""
  EOT
  description = "Express-based setup server script"
}
