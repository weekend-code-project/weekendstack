# =============================================================================
# Setup Server Module - Shared Git Module
# =============================================================================
# This module handles server setup for any template type. Templates provide
# their specific server command, HTML content, and optional pre-setup logic.

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

variable "workspace_id" {
  description = "Workspace ID for deterministic port generation"
  type        = string
}

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

variable "host_ip" {
  description = "Host IP address for external access"
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

# =============================================================================
# Port Generation
# =============================================================================
# Generate deterministic external ports based on workspace ID
# This ensures each workspace gets consistent ports across restarts

# Generate external ports for each exposed port (range: 18000-18999)
resource "random_integer" "external_ports" {
  count = length(var.exposed_ports_list)
  
  min = 18000 + (count.index * 100)
  max = 18000 + (count.index * 100) + 99
  
  keepers = {
    workspace_id = var.workspace_id
    port_index   = count.index
  }
}

locals {
  # Map internal ports to external ports
  port_mappings = [
    for idx, internal_port in var.exposed_ports_list : {
      internal = tonumber(internal_port)
      external = random_integer.external_ports[idx].result
    }
  ]
  
  # Primary port (first in list)
  primary_internal_port = element(var.exposed_ports_list, 0)
  primary_external_port = random_integer.external_ports[0].result
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
    
    # Navigate to workspace directory (should be created by init-shell module)
    cd /home/coder/workspace
    
    AUTO_HTML="${var.auto_generate_html}"

    # Auto-generate HTML if enabled
    if [ "$AUTO_HTML" = "true" ]; then
      if [ ! -f index.html ]; then
  # Use an unquoted heredoc so shell variables like $PORT expand
  cat <<-HTML > index.html 2>/dev/null
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
  echo "[SETUP-SERVER] ✅ Created index.html"
      else
        echo "[SETUP-SERVER] ✅ Using existing index.html"
      fi
    fi
    
    # Run pre-server setup if provided
    ${var.pre_server_setup != "" ? "${var.pre_server_setup} >/dev/null 2>&1" : ""}
    
    # Check if custom startup command is provided
    STARTUP_CMD="${var.startup_command}"
    if [ -n "$STARTUP_CMD" ] && [ "$STARTUP_CMD" != "" ]; then
      nohup bash -c "$STARTUP_CMD" > /tmp/custom-server.log 2>&1 &
      echo $! > /tmp/custom-server.pid
      sleep 1
      if ps -p $(cat /tmp/custom-server.pid) >/dev/null 2>&1; then
        echo "[SETUP-SERVER] ✅ Custom command: $STARTUP_CMD (PID: $(cat /tmp/custom-server.pid))"
      else
        echo "[SETUP-SERVER] ❌ Custom command failed - check: tail /tmp/custom-server.log"
      fi
    elif [ "$AUTO_HTML" = "true" ]; then
      # Start default server in background
      nohup bash -c "${var.default_server_command}" > ${var.server_log_file} 2>&1 &
      echo $! > ${var.server_pid_file}
      sleep 2
      if ps -p $(cat ${var.server_pid_file}) >/dev/null 2>&1; then
        echo "[SETUP-SERVER] ✅ ${var.server_name} running on port $PORT (PID: $(cat ${var.server_pid_file}))"
        echo "[SETUP-SERVER] 🌐 External access: http://${var.host_ip}:${local.primary_external_port}"
      else
        echo "[SETUP-SERVER] ❌ ${var.server_name} failed to start - check: tail ${var.server_log_file}"
      fi
    fi

  EOT
}

# =============================================================================
# Outputs
# =============================================================================

output "docker_ports" {
  description = "Docker port mappings for exposed server ports"
  value       = local.port_mappings
}

output "primary_external_port" {
  description = "Primary external port for accessing the server"
  value       = local.primary_external_port
}

output "metadata_blocks" {
  description = "Metadata blocks contributed by this module"
  value = [
    {
      display_name = "Server Port"
      script       = "echo ${local.primary_external_port}"
      interval     = 60
      timeout      = 1
    }
  ]
}
