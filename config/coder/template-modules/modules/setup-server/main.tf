# =============================================================================
# Setup Server Module - Shared Git Module
# =============================================================================
# This module handles server setup for any template type. Templates provide
# their specific server command, HTML content, and optional pre-setup logic.

variable "exposed_ports_list" {
  description = "List of ports to expose"
  type        = list(string)
}

variable "default_server_command" {
  description = "Default command to start the server (e.g., 'python3 -m http.server $PORT')"
  type        = string
}

variable "server_name" {
  description = "Display name of the server (e.g., 'Python 3 HTTP Server')"
  type        = string
}

variable "server_log_file" {
  description = "Path to server log file"
  type        = string
  default     = "/tmp/server.log"
}

variable "server_pid_file" {
  description = "Path to server PID file"
  type        = string
  default     = "/tmp/server.pid"
}

variable "html_status_message" {
  description = "Status message to display in generated HTML"
  type        = string
  default     = "Server is running!"
}

variable "html_server_info" {
  description = "Server info to display in generated HTML"
  type        = string
  default     = "Server running on port $PORT"
}

variable "html_instructions" {
  description = "Getting started instructions for generated HTML"
  type        = string
  default     = ""
}

variable "pre_server_setup" {
  description = "Optional script to run before starting server"
  type        = string
  default     = ""
}

variable "workspace_name" {
  description = "Workspace name for HTML generation"
  type        = string
}

variable "workspace_owner" {
  description = "Workspace owner for HTML generation"
  type        = string
}

variable "auto_generate_html" {
  description = "Whether to auto-generate index.html"
  type        = string
}

variable "startup_command" {
  description = "Custom startup command (if provided)"
  type        = string
}

# Output the setup script
output "setup_server_script" {
  value = <<-EOT
    #!/bin/bash
    # Setup Server (${var.server_name})
    set -e
    
    # Export ports computed by Terraform
    export PORTS="${join(",", var.exposed_ports_list)}"
    export PORT="${element(var.exposed_ports_list, 0)}"
    
    echo "[SETUP-SERVER] Configuring workspace server..."
    echo "[SETUP-SERVER] Port: $PORT"
    
    # Navigate to workspace directory (should be created by init-shell module)
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
        pre {
            background: #f5f5f5;
            padding: 15px;
            border-radius: 4px;
            overflow-x: auto;
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
      <strong>Status:</strong> ${var.html_status_message}
    </div>
        
    <div class="info">
      <strong>Currently Serving:</strong><br>
      ${var.html_server_info}
    </div>
        
    <h2>Getting Started</h2>
        <p>This workspace is running ${var.server_name}.</p>
        
        <pre><code>${var.html_instructions}</code></pre>
        
    <h2>Workspace Info</h2>
    <ul>
      <li><strong>Owner:</strong> ${var.workspace_owner}</li>
      <li><strong>Port:</strong> $PORT</li>
      <li><strong>Server:</strong> ${var.server_name}</li>
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
    
    # Run pre-server setup if provided
    ${var.pre_server_setup != "" ? "echo \"[SETUP-SERVER] Running pre-server setup...\"\n${var.pre_server_setup}" : ""}
    
    # Check if custom startup command is provided
    STARTUP_CMD="${var.startup_command}"
    if [ -n "$STARTUP_CMD" ] && [ "$STARTUP_CMD" != "" ]; then
      echo "[SETUP-SERVER] Running custom startup command..."
      echo "[SETUP-SERVER] Command: $STARTUP_CMD"
      nohup bash -c "$STARTUP_CMD" > /tmp/custom-server.log 2>&1 &
      echo $! > /tmp/custom-server.pid
      sleep 1
      if ps -p $(cat /tmp/custom-server.pid) > /dev/null 2>&1; then
        echo "[SETUP-SERVER] ✓ Custom command started (PID: $(cat /tmp/custom-server.pid))"
      else
        echo "[SETUP-SERVER] ⚠ Custom command may have failed to start"
        echo "[SETUP-SERVER] Check logs: tail /tmp/custom-server.log"
      fi
    elif [ "$AUTO_HTML" = "true" ]; then
      # Start default server in background
      echo "[SETUP-SERVER] Starting ${var.server_name}..."
      echo "[SETUP-SERVER] Server will be available at http://localhost:$PORT"
      nohup bash -c "${var.default_server_command}" > ${var.server_log_file} 2>&1 &
      echo $! > ${var.server_pid_file}
      sleep 2
      if ps -p $(cat ${var.server_pid_file}) > /dev/null 2>&1; then
        echo "[SETUP-SERVER] ✓ ${var.server_name} started (PID: $(cat ${var.server_pid_file}))"
      else
        echo "[SETUP-SERVER] ⚠ ${var.server_name} may have failed to start"
        echo "[SETUP-SERVER] Check logs: tail ${var.server_log_file}"
      fi
    else
      echo "[SETUP-SERVER] Auto HTML disabled and no startup command provided; not starting a server."
    fi

    echo ""
  EOT
}
