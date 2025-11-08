# =============================================================================terraform {

# Setup Server Module - Shared Git Module  required_providers {

# =============================================================================    coder = {

# This module handles server setup for any template type. Templates provide      source = "coder/coder"

# their specific server command, HTML content, and optional pre-setup logic.    }

#  }

# Usage:}

#   module "setup_server" {

#     source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.1"# =============================================================================

#     # Setup Server Module

#     # Port configuration# =============================================================================

#     exposed_ports_list = ["8080"]# Prepares the workspace for serving content by setting up PORT environment

#     # variable and optionally auto-generating a default index.html file.

#     # Template-specific configuration# 

#     default_server_command = "python3 -m http.server $PORT --bind 0.0.0.0"# This module ONLY handles server setup - preview link logic is decoupled

#     server_name = "Python 3 HTTP Server"# to the preview-link module.

#     server_log_file = "/tmp/http-server.log"

#     server_pid_file = "/tmp/http-server.pid"variable "workspace_name" {

#       description = "Name of the workspace"

#     # HTML content (optional - for static site toggle)  type        = string

#     html_status_message = "Python HTTP server is running!"}

#     html_server_info = "Python 3 HTTP server on port $PORT"

#     html_instructions = <<-INSTRUCTIONSvariable "workspace_owner" {

#       # Edit the current page  description = "Owner of the workspace"

#       vi index.html  type        = string

#       }

#       # Or create your own site

#       mkdir -p mysitevariable "auto_generate_html" {

#       cd mysite  description = "Whether to auto-generate default index.html"

#       echo "&lt;h1&gt;Hello World&lt;/h1&gt;" &gt; index.html  type        = bool

#         default     = true

#       # Restart the server}

#       pkill -f "python3 -m http.server"

#       python3 -m http.server $PORTvariable "exposed_ports_list" {

#     INSTRUCTIONS  description = "List of exposed ports"

#       type        = list(string)

#     # Optional: Script to run before starting server (e.g., npm init, install deps)}

#     pre_server_setup = ""

#     variable "startup_command" {

#     # Workspace metadata  description = "Optional startup command"

#     workspace_name = data.coder_workspace.me.name  type        = string

#     workspace_owner = data.coder_workspace_owner.me.name  default     = ""

#     }

#     # Parameters from shared module

#     auto_generate_html = data.coder_parameter.auto_generate_html.value# =============================================================================

#     startup_command = var.startup_cmd_value# Setup Script

#   }# =============================================================================



variable "exposed_ports_list" {# Setup server script

  description = "List of ports to expose"output "setup_server_script" {

  type        = list(string)  value = <<-EOT

}    #!/bin/bash

    # Setup Server

variable "default_server_command" {    set -e

  description = "Default command to start the server (e.g., 'python3 -m http.server $PORT')"    

  type        = string    # Export ports computed by Terraform

}    export PORTS="${join(",", var.exposed_ports_list)}"

    export PORT="${element(var.exposed_ports_list, 0)}"

variable "server_name" {    

  description = "Display name of the server (e.g., 'Python 3 HTTP Server')"    echo "[SETUP-SERVER] Configuring workspace server..."

  type        = string    echo "[SETUP-SERVER] Port: $PORT"

}    

    # Navigate to workspace directory (should be created by init-shell module)

variable "server_log_file" {    cd /home/coder/workspace

  description = "Path to server log file"    

  type        = string    AUTO_HTML="${var.auto_generate_html}"

  default     = "/tmp/server.log"

}    # Auto-generate HTML if enabled

    if [ "$AUTO_HTML" = "true" ]; then

variable "server_pid_file" {      if [ ! -f index.html ]; then

  description = "Path to server PID file"  echo "[SETUP-SERVER] Creating default index.html..."

  type        = string  # Use an unquoted heredoc so shell variables like $PORT expand

  default     = "/tmp/server.pid"  cat <<-HTML > index.html

}<!DOCTYPE html>

<html lang="en">

variable "html_status_message" {<head>

  description = "Status message to display in generated HTML"    <meta charset="UTF-8">

  type        = string    <meta name="viewport" content="width=device-width, initial-scale=1.0">

  default     = "Server is running!"    <title>Coder Workspace - ${var.workspace_name}</title>

}    <style>

        body {

variable "html_server_info" {            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;

  description = "Server info to display in generated HTML"            max-width: 800px;

  type        = string            margin: 50px auto;

  default     = "Server running on port $PORT"            padding: 20px;

}            line-height: 1.6;

            background: #f5f5f5;

variable "html_instructions" {        }

  description = "Getting started instructions for generated HTML"        .container {

  type        = string            background: white;

  default     = ""            padding: 40px;

}            border-radius: 8px;

            box-shadow: 0 2px 4px rgba(0,0,0,0.1);

variable "pre_server_setup" {        }

  description = "Optional script to run before starting server (e.g., npm init, install dependencies)"        h1 { color: #333; margin-top: 0; }

  type        = string        .status { 

  default     = ""            background: #e8f5e9;

}            padding: 15px;

            border-radius: 4px;

variable "workspace_name" {            border-left: 4px solid #4caf50;

  description = "Workspace name for HTML generation"            margin: 20px 0;

  type        = string        }

}        .info {

            background: #e3f2fd;

variable "workspace_owner" {            padding: 15px;

  description = "Workspace owner for HTML generation"            border-radius: 4px;

  type        = string            border-left: 4px solid #2196f3;

}            margin: 20px 0;

        }

variable "auto_generate_html" {        code {

  description = "Whether to auto-generate index.html"            background: #f5f5f5;

  type        = string            padding: 2px 6px;

}            border-radius: 3px;

            font-family: 'Monaco', 'Courier New', monospace;

variable "startup_command" {        }

  description = "Custom startup command (if provided)"        a { color: #1976d2; text-decoration: none; }

  type        = string        a:hover { text-decoration: underline; }

}        .footer {

            margin-top: 40px;

# Output the setup script            padding-top: 20px;

output "setup_server_script" {            border-top: 1px solid #eee;

  value = <<-EOT            color: #666;

    #!/bin/bash            font-size: 14px;

    # Setup Server (${var.server_name})        }

    set -e    </style>

    </head>

    # Export ports computed by Terraform<body>

    export PORTS="${join(",", var.exposed_ports_list)}"    <div class="container">

    export PORT="${element(var.exposed_ports_list, 0)}"    <h1>Workspace: ${var.workspace_name}</h1>

            

    echo "[SETUP-SERVER] Configuring workspace server..."    <div class="status">

    echo "[SETUP-SERVER] Port: $PORT"      <strong>Status:</strong> Workspace is running!

        </div>

    # Navigate to workspace directory (should be created by init-shell module)        

    cd /home/coder/workspace    <h2>Getting Started</h2>

            <p>This is a default page. Replace <code>index.html</code> with your own content, or start your application:</p>

    AUTO_HTML="${var.auto_generate_html}"        

        <pre><code># Python

    # Auto-generate HTML if enabledpython3 -m http.server $PORT

    if [ "$AUTO_HTML" = "true" ]; then

      if [ ! -f index.html ]; then# Node.js

  echo "[SETUP-SERVER] Creating default index.html..."npx http-server -p $PORT

  # Use an unquoted heredoc so shell variables like $PORT expand

  cat <<-HTML > index.html# Your custom app

<!DOCTYPE html>npm start</code></pre>

<html lang="en">        

<head>    <h2>Workspace Info</h2>

    <meta charset="UTF-8">    <ul>

    <meta name="viewport" content="width=device-width, initial-scale=1.0">      <li><strong>Owner:</strong> ${var.workspace_owner}</li>

    <title>Coder Workspace - ${var.workspace_name}</title>      <li><strong>Port:</strong> $PORT</li>

    <style>    </ul>

        body {        

            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;        <div class="footer">

            max-width: 800px;            <!-- auto-generated by Coder -->

            margin: 50px auto;            <em>This page was auto-generated. Disable in workspace settings if not needed.</em>

            padding: 20px;        </div>

            line-height: 1.6;    </div>

            background: #f5f5f5;</body>

        }</html>

        .container {HTML

            background: white;  echo "[SETUP-SERVER] ✓ index.html created"

            padding: 40px;      else

            border-radius: 8px;        echo "[SETUP-SERVER] ✓ index.html already exists (leaving as-is)"

            box-shadow: 0 2px 4px rgba(0,0,0,0.1);      fi

        }    fi

        h1 { color: #333; margin-top: 0; }    

        .status {     # Check if custom startup command is provided

            background: #e8f5e9;    STARTUP_CMD="${var.startup_command}" 

            padding: 15px;    if [ -n "$STARTUP_CMD" ] && [ "$STARTUP_CMD" != "" ]; then

            border-radius: 4px;      echo "[SETUP-SERVER] Running custom startup command..."

            border-left: 4px solid #4caf50;      echo "[SETUP-SERVER] Command: $STARTUP_CMD"

            margin: 20px 0;      eval "$STARTUP_CMD" &

        }      echo "[SETUP-SERVER] ✓ Custom command started in background"

        .info {    elif [ "$AUTO_HTML" = "true" ]; then

            background: #e3f2fd;      # Start default Python HTTP server in background

            padding: 15px;      echo "[SETUP-SERVER] Starting default HTTP server..."

            border-radius: 4px;      echo "[SETUP-SERVER] Server will be available at http://localhost:$PORT"

            border-left: 4px solid #2196f3;      nohup python3 -m http.server $PORT --bind 0.0.0.0 > /tmp/http-server.log 2>&1 &

            margin: 20px 0;      echo $! > /tmp/http-server.pid

        }      sleep 2

        code {      if ps -p $(cat /tmp/http-server.pid) > /dev/null 2>&1; then

            background: #f5f5f5;        echo "[SETUP-SERVER] ✓ HTTP server started (PID: $(cat /tmp/http-server.pid))"

            padding: 2px 6px;      else

            border-radius: 3px;        echo "[SETUP-SERVER] ⚠ HTTP server may have failed to start"

            font-family: 'Monaco', 'Courier New', monospace;        echo "[SETUP-SERVER] Check logs: tail /tmp/http-server.log"

        }      fi

        pre {    else

            background: #f5f5f5;      echo "[SETUP-SERVER] Auto HTML disabled and no startup command provided; not starting a server."

            padding: 15px;    fi

            border-radius: 4px;    

            overflow-x: auto;    echo ""

        }  EOT

        a { color: #1976d2; text-decoration: none; }}

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
    
    # Run pre-server setup if provided (e.g., npm init, install dependencies)
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
