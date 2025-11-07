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
    if [ ! -f package.json ]; then
      echo "[NODE-SERVER] Initializing package.json"
      npm init -y >/dev/null 2>&1 || true
      # Create simple server using http module (no deps)
      cat > server.js <<'JS'
const http = require('http');
const port = process.env.PORT || ${element(var.exposed_ports, 0)};
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8'});
  res.end(`<h1>Welcome to your Node Workspace</h1><p>Listening on port ${'$'}{port}</p>`);
});
server.listen(port, '0.0.0.0', () => console.log(`Server running on http://localhost:${'$'}{port}`));
JS
      # Add start script
      node -e "const fs=require('fs'); const pkg=JSON.parse(fs.readFileSync('package.json')); pkg.scripts=pkg.scripts||{}; pkg.scripts.start='node server.js'; fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));"
      echo "[NODE-SERVER] Default server scaffolded"
    else
      echo "[NODE-SERVER] Existing package.json detected; not scaffolding"
    fi
    export PORT=${element(var.exposed_ports, 0)}
    echo "[NODE-SERVER] Starting server on $PORT"
    npm run start --if-present &
    echo "[NODE-SERVER] Done."
    echo ""
  EOT
}

output "node_server_script" {
  description = "Script to scaffold and start Node server"
  value       = local.node_server_script
}
