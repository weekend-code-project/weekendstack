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

variable "agent_id" {
  description = "Coder agent ID for the preview button"
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

variable "pre_server_setup" {
  description = "Optional script to run before starting server"
  type        = string
  default     = ""
}

variable "workspace_name" {
  description = "Workspace name for HTML generation"
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

variable "server_stop_command" {
  description = "Command to stop the server (displayed in index.html)"
  type        = string
  default     = "pkill -f \"python3 -m http.server\""
}

variable "server_restart_command" {
  description = "Command to restart the server (displayed in index.html)"
  type        = string
  default     = "python3 -m http.server $PORT"
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
  
  # Port range display for multiple ports
  num_ports = length(var.exposed_ports_list)
  port_display = local.num_ports == 1 ? tostring(local.primary_external_port) : "${local.primary_external_port}-${random_integer.external_ports[local.num_ports - 1].result}"
  
  # Access URL
  access_url = "http://${var.host_ip}:${local.port_display}"
}

# Output the setup script
output "setup_server_script" {
  value = <<-EOT
    #!/bin/bash
    # Setup Server (${var.server_name})
    set -e
    
    # Export internal ports (for binding inside container)
    export PORTS="${join(",", var.exposed_ports_list)}"
    export PORT="${element(var.exposed_ports_list, 0)}"
%{for idx, port in var.exposed_ports_list~}
%{if idx > 0~}
    export PORT${idx + 1}="${port}"
%{endif~}
%{endfor~}
    
    # Navigate to workspace directory (should be created by init-shell module)
    echo "[SETUP-SERVER] 🔧 Starting setup..."
    echo "[SETUP-SERVER] 📂 Current directory: $(pwd)"
    cd /home/coder/workspace
    echo "[SETUP-SERVER] 📂 Changed to workspace: $(pwd)"
    echo "[SETUP-SERVER] 📋 Workspace contents: $(ls -la)"
    
    AUTO_HTML="${var.auto_generate_html}"
    echo "[SETUP-SERVER] 🎨 HTML generation toggle: $AUTO_HTML"

    # Auto-generate HTML if enabled (always regenerate to reflect current settings)
    if [ "$AUTO_HTML" = "true" ]; then
        echo "[SETUP-SERVER] 🗑️  Removing old index.html..."
        rm -f index.html
        echo "[SETUP-SERVER] ✍️  Generating new index.html..."
        # Use an unquoted heredoc so shell variables like $PORT expand
        cat <<-HTML > index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${var.workspace_name}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 600px;
            margin: 80px auto;
            padding: 20px;
            line-height: 1.6;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        h1 { 
            color: #333; 
            margin-top: 0;
            font-size: 2em;
        }
        .status { 
            background: #e8f5e9;
            padding: 20px;
            border-radius: 4px;
            margin: 30px 0;
            font-size: 1.1em;
        }
        .access {
            background: #e3f2fd;
            padding: 20px;
            border-radius: 4px;
            margin: 20px 0;
        }
        .url {
            font-size: 1.2em;
            color: #1976d2;
            font-weight: bold;
            word-break: break-all;
        }
        code {
            background: #f5f5f5;
            padding: 2px 8px;
            border-radius: 3px;
            font-family: 'Monaco', 'Courier New', monospace;
        }
        pre {
            background: #f5f5f5;
            padding: 15px;
            border-radius: 4px;
            overflow-x: auto;
            text-align: left;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background: white;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }
        th {
            background: #f5f5f5;
            font-weight: 600;
            color: #666;
        }
        tr:hover {
            background: #fafafa;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            color: #999;
            font-size: 0.85em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>${var.workspace_name}</h1>
        
        <div class="status">
            ✅ Server Running
        </div>
        
        <div class="access">
            <div style="margin-bottom: 10px;">Access your server at:</div>
            <div class="url">${local.access_url}</div>
        </div>
        ${local.num_ports > 1 ? <<-PORTS

        <h3>Port Mapping</h3>
        <table>
            <thead>
                <tr>
                    <th>Environment Variable</th>
                    <th>Internal Port</th>
                    <th>External Port (Network Access)</th>
                </tr>
            </thead>
            <tbody>
%{for idx, mapping in local.port_mappings~}
                <tr>
                    <td><code>\$PORT${idx == 0 ? "" : idx + 1}</code></td>
                    <td>${mapping.internal}</td>
                    <td>${mapping.external}</td>
                </tr>
%{endfor~}
            </tbody>
        </table>
PORTS
 : ""}
        
        <h3>Manage Server</h3>
        <pre><code># Stop the server
${var.server_stop_command}

# Restart the server (uses \$PORT=${local.primary_internal_port})
${var.server_restart_command}</code></pre>
        
        <p style="font-size: 0.9em; color: #666; margin-top: 20px;">
            💡 <strong>Port Mapping:</strong> Internal port ${local.primary_internal_port} (default) maps to external ${local.primary_external_port}
        </p>
        
        <div class="footer">
            Auto-generated by Coder
        </div>
    </div>
</body>
</html>
HTML
  echo "[SETUP-SERVER] ✅ Generated index.html with current port mappings"
  echo "[SETUP-SERVER] 📄 File check: $(ls -lh index.html 2>&1)"
  echo "[SETUP-SERVER] 📏 File size: $(wc -c < index.html 2>&1) bytes"
    else
      echo "[SETUP-SERVER] ⚠️  HTML generation disabled (AUTO_HTML=$AUTO_HTML)"
    fi
    
    # Run pre-server setup if provided
    ${var.pre_server_setup != "" ? "${var.pre_server_setup} >/dev/null 2>&1" : ""}
    
    # Display port information (always shown)
    NUM_PORTS=${local.num_ports}
    echo "[SETUP-SERVER] 🌐 Access: ${local.access_url}"
    echo "[SETUP-SERVER] 🔌 Number of ports: $NUM_PORTS"
    if [ "$NUM_PORTS" = "1" ]; then
      echo "[SETUP-SERVER] 📊 Port Mapping:"
      echo "┌──────────┬──────────┬──────────┐"
      echo "│ Variable │ Internal │ External │"
      echo "├──────────┼──────────┼──────────┤"
      printf "│ %-8s │ %-8s │ %-8s │\n" "\$PORT" "${element(var.exposed_ports_list, 0)}" "${local.primary_external_port}"
      echo "└──────────┴──────────┴──────────┘"
    else
      echo "[SETUP-SERVER] 📊 Port Mappings:"
      echo "┌──────────┬──────────┬──────────┐"
      echo "│ Variable │ Internal │ External │"
      echo "├──────────┼──────────┼──────────┤"
%{for idx, mapping in local.port_mappings~}
      printf "│ %-8s │ %-8s │ %-8s │\n" "\$PORT${idx == 0 ? "" : idx + 1}" "${mapping.internal}" "${mapping.external}"
%{endfor~}
      echo "└──────────┴──────────┴──────────┘"
    fi
    
    # Check if custom startup command is provided
    STARTUP_CMD="${var.startup_command}"
    echo "[SETUP-SERVER] 🚀 Startup command: $STARTUP_CMD"
    if [ -n "$STARTUP_CMD" ] && [ "$STARTUP_CMD" != "" ]; then
      echo "[SETUP-SERVER] 📝 Creating wrapper script..."
      # Create wrapper script for proper background execution
      cat > /tmp/startup-wrapper.sh << WRAPPER_EOF
#!/bin/bash
exec $STARTUP_CMD
WRAPPER_EOF
      chmod +x /tmp/startup-wrapper.sh
      echo "[SETUP-SERVER] 🔧 Wrapper script created at /tmp/startup-wrapper.sh"
      echo "[SETUP-SERVER] 📜 Wrapper contents: $(cat /tmp/startup-wrapper.sh)"
      
      # Run wrapper script with nohup for process persistence
      echo "[SETUP-SERVER] 🏃 Starting server in background..."
      nohup /tmp/startup-wrapper.sh > /tmp/custom-server.log 2>&1 &
      echo $! > /tmp/custom-server.pid
      echo "[SETUP-SERVER] 💤 Waiting 3 seconds for server to start..."
      sleep 3
      if ps -p $(cat /tmp/custom-server.pid) >/dev/null 2>&1; then
        echo "[SETUP-SERVER] ✅ Custom command: $STARTUP_CMD (PID: $(cat /tmp/custom-server.pid))"
        echo "[SETUP-SERVER] 📋 Server log preview:"
        head -20 /tmp/custom-server.log 2>&1 | sed 's/^/[SETUP-SERVER]   /'
      else
        echo "[SETUP-SERVER] ❌ Custom command failed - check: tail /tmp/custom-server.log"
        echo "[SETUP-SERVER] 📋 Error log:"
        tail -20 /tmp/custom-server.log 2>&1 | sed 's/^/[SETUP-SERVER]   /'
      fi
    elif [ "$AUTO_HTML" = "true" ]; then
      echo "[SETUP-SERVER] 🏃 Starting default server: ${var.default_server_command}"
      # Start default server in background
      nohup bash -c "${var.default_server_command}" > ${var.server_log_file} 2>&1 &
      echo $! > ${var.server_pid_file}
      echo "[SETUP-SERVER] 💤 Waiting 2 seconds for server to start..."
      sleep 2
      if ps -p $(cat ${var.server_pid_file}) >/dev/null 2>&1; then
        echo "[SETUP-SERVER] ✅ ${var.server_name} running on port $PORT (PID: $(cat ${var.server_pid_file}))"
      else
        echo "[SETUP-SERVER] ❌ ${var.server_name} failed to start - check: tail ${var.server_log_file}"
        echo "[SETUP-SERVER] 📋 Error log:"
        tail -20 ${var.server_log_file} 2>&1 | sed 's/^/[SETUP-SERVER]   /'
      fi
    else
      echo "[SETUP-SERVER] ⚠️  No server command configured"
    fi
    
    echo ""
    echo "[SETUP-SERVER] 🏁 Setup complete!"
    echo "[SETUP-SERVER] 📂 Workspace directory contents:"
    ls -lah /home/coder/workspace | sed 's/^/[SETUP-SERVER]   /'
    echo ""  # Line break after module

  EOT
}

# =============================================================================
# Preview Button - Direct IP Access
# =============================================================================
# NOTE: Commented out in favor of unified preview button in traefik-routing module
# The traefik-routing module provides a single "Preview" button that switches between
# internal (Coder proxy) and external (Traefik subdomain) based on preview_mode parameter

# resource "coder_app" "preview_server" {
#   agent_id     = var.agent_id
#   slug         = "direct-preview"
#   display_name = "Local Preview"
#   url          = "http://${var.host_ip}:${local.primary_external_port}"
#   icon         = "/icon/coder.svg"
#   external     = true
# }

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
      display_name = "Server Ports"
      script       = "echo ${local.port_display}"
      interval     = 60
      timeout      = 1
    }
  ]
}
