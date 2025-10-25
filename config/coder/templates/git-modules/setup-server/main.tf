terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# Setup Server Module
# =============================================================================
# Prepares the workspace for serving content by setting up PORT environment
# variable and optionally auto-generating a default index.html file.

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

# =============================================================================
# Preview App
# =============================================================================

resource "coder_app" "preview" {
  count        = var.workspace_start_count
  agent_id     = var.agent_id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/icon/code.svg"
  url          = "http://localhost:${element(var.exposed_ports_list, 0)}"
  subdomain    = false
  share        = "owner"
  
  healthcheck {
    url       = "http://localhost:${element(var.exposed_ports_list, 0)}"
    interval  = 5
    threshold = 6
  }
}

# =============================================================================
# Setup Script
# =============================================================================

# Setup server script
output "setup_server_script" {
  value = <<-EOT
    #!/bin/bash
    # Setup Server
    set -e
    
    # Export ports computed by Terraform
    export PORTS="${join(",", var.exposed_ports_list)}"
    export PORT="${element(var.exposed_ports_list, 0)}"
    
    echo "[SETUP-SERVER] Configuring workspace server..."
    echo "[SETUP-SERVER] Port: $PORT"
    
    # Navigate to workspace directory (create if it doesn't exist)
    mkdir -p /home/coder/workspace
    cd /home/coder/workspace
    
    AUTO_HTML="${var.auto_generate_html}"

    # Auto-generate HTML if enabled
    if [ "$AUTO_HTML" = "true" ]; then
      if [ ! -f index.html ]; then
  echo "[SETUP-SERVER] Creating default index.html..."
  # Use an unquoted heredoc so shell variables like $PORT expand
  cat <<-HTML > index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Coder Workspace - ${var.workspace_name}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            line-height: 1.6;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; margin-top: 0; }
        .status { 
            background: #e8f5e9;
            padding: 15px;
            border-radius: 4px;
            border-left: 4px solid #4caf50;
            margin: 20px 0;
        }
        .info {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 4px;
            border-left: 4px solid #2196f3;
            margin: 20px 0;
        }
        code {
            background: #f5f5f5;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
        }
        a { color: #1976d2; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #666;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
    <h1>Workspace: ${var.workspace_name}</h1>
        
    <div class="status">
      <strong>Status:</strong> Workspace is running!
    </div>
        
    <div class="info">
      <strong>Access URLs:</strong><br>
      <ul>
        <li>External: <a href="https://${lower(var.workspace_name)}.weekendcodeproject.dev">https://${lower(var.workspace_name)}.weekendcodeproject.dev</a></li>
      </ul>
    </div>
        
    <h2>Getting Started</h2>
        <p>This is a default page. Replace <code>index.html</code> with your own content, or start your application:</p>
        
        <pre><code># Python
python3 -m http.server $PORT

# Node.js
npx http-server -p $PORT

# Your custom app
npm start</code></pre>
        
    <h2>Workspace Info</h2>
    <ul>
      <li><strong>Owner:</strong> ${var.workspace_owner}</li>
      <li><strong>Port:</strong> $PORT</li>
    </ul>
        
        <div class="footer">
            <!-- auto-generated by Coder -->
            <em>This page was auto-generated. Disable in workspace settings if not needed.</em>
        </div>
    </div>
</body>
</html>
HTML
  echo "[SETUP-SERVER] ✓ index.html created"
      else
        echo "[SETUP-SERVER] ✓ index.html already exists (leaving as-is)"
      fi
    fi
    
    # Check if custom startup command is provided
    STARTUP_CMD="${var.startup_command}" 
    if [ -n "$STARTUP_CMD" ] && [ "$STARTUP_CMD" != "" ]; then
      echo "[SETUP-SERVER] Running custom startup command..."
      echo "[SETUP-SERVER] Command: $STARTUP_CMD"
      eval "$STARTUP_CMD" &
      echo "[SETUP-SERVER] ✓ Custom command started in background"
    elif [ "$AUTO_HTML" = "true" ]; then
      # Start default Python HTTP server in background
      echo "[SETUP-SERVER] Starting default HTTP server..."
      echo "[SETUP-SERVER] Server will be available at http://localhost:$PORT"
      nohup python3 -m http.server $PORT --bind 0.0.0.0 > /tmp/http-server.log 2>&1 &
      echo $! > /tmp/http-server.pid
      sleep 2
      if ps -p $(cat /tmp/http-server.pid) > /dev/null 2>&1; then
        echo "[SETUP-SERVER] ✓ HTTP server started (PID: $(cat /tmp/http-server.pid))"
      else
        echo "[SETUP-SERVER] ⚠ HTTP server may have failed to start"
        echo "[SETUP-SERVER] Check logs: tail /tmp/http-server.log"
      fi
    else
      echo "[SETUP-SERVER] Auto HTML disabled and no startup command provided; not starting a server."
    fi
    
    echo ""
  EOT
}
