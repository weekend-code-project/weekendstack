# =============================================================================# =============================================================================terraform {

# Setup Server Module - Shared Git Module

# =============================================================================# Setup Server Module - Shared Git Module  required_providers {

# This module handles server setup for any template type. Templates provide

# their specific server command, HTML content, and optional pre-setup logic.# =============================================================================    coder = {

#

# Usage:# This module handles server setup for any template type. Templates provide      source = "coder/coder"

#   module "setup_server" {

#     source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.1"# their specific server command, HTML content, and optional pre-setup logic.    }

#     

#     # Port configuration#  }

#     exposed_ports_list = ["8080"]

#     # Usage:}

#     # Template-specific configuration

#     default_server_command = "python3 -m http.server $PORT --bind 0.0.0.0"#   module "setup_server" {

#     server_name = "Python 3 HTTP Server"

#     server_log_file = "/tmp/http-server.log"#     source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.1"# =============================================================================

#     server_pid_file = "/tmp/http-server.pid"

#     #     # Setup Server Module

#     # HTML content (optional - for static site toggle)

#     html_status_message = "Python HTTP server is running!"#     # Port configuration# =============================================================================

#     html_server_info = "Python 3 HTTP server on port $PORT"

#     html_instructions = <<-INSTRUCTIONS#     exposed_ports_list = ["8080"]# Prepares the workspace for serving content by setting up PORT environment

#       # Edit the current page

#       vi index.html#     # variable and optionally auto-generating a default index.html file.

#       

#       # Or create your own site#     # Template-specific configuration# 

#       mkdir -p mysite

#       cd mysite#     default_server_command = "python3 -m http.server $PORT --bind 0.0.0.0"# This module ONLY handles server setup - preview link logic is decoupled

#       echo "&lt;h1&gt;Hello World&lt;/h1&gt;" &gt; index.html

#       #     server_name = "Python 3 HTTP Server"# to the preview-link module.

#       # Restart the server

#       pkill -f "python3 -m http.server"#     server_log_file = "/tmp/http-server.log"

#       python3 -m http.server $PORT

#     INSTRUCTIONS#     server_pid_file = "/tmp/http-server.pid"variable "workspace_name" {

#     

#     # Optional: Script to run before starting server (e.g., npm init, install deps)#       description = "Name of the workspace"

#     pre_server_setup = ""

#     #     # HTML content (optional - for static site toggle)  type        = string

#     # Workspace metadata

#     workspace_name = data.coder_workspace.me.name#     html_status_message = "Python HTTP server is running!"}

#     workspace_owner = data.coder_workspace_owner.me.name

#     #     html_server_info = "Python 3 HTTP server on port $PORT"

#     # Parameters from shared module

#     auto_generate_html = data.coder_parameter.auto_generate_html.value#     html_instructions = <<-INSTRUCTIONSvariable "workspace_owner" {

#     startup_command = var.startup_cmd_value

#   }#       # Edit the current page  description = "Owner of the workspace"



variable "exposed_ports_list" {#       vi index.html  type        = string

  description = "List of ports to expose"

  type        = list(string)#       }

}

#       # Or create your own site

variable "default_server_command" {

  description = "Default command to start the server (e.g., 'python3 -m http.server $PORT')"#       mkdir -p mysitevariable "auto_generate_html" {

  type        = string

}#       cd mysite  description = "Whether to auto-generate default index.html"



variable "server_name" {#       echo "&lt;h1&gt;Hello World&lt;/h1&gt;" &gt; index.html  type        = bool

  description = "Display name of the server (e.g., 'Python 3 HTTP Server')"

  type        = string#         default     = true

}

#       # Restart the server}

variable "server_log_file" {

  description = "Path to server log file"#       pkill -f "python3 -m http.server"

  type        = string

  default     = "/tmp/server.log"#       python3 -m http.server $PORTvariable "exposed_ports_list" {

}

#     INSTRUCTIONS  description = "List of exposed ports"

variable "server_pid_file" {

  description = "Path to server PID file"#       type        = list(string)

  type        = string

  default     = "/tmp/server.pid"#     # Optional: Script to run before starting server (e.g., npm init, install deps)}

}

#     pre_server_setup = ""

variable "html_status_message" {

  description = "Status message to display in generated HTML"#     variable "startup_command" {

  type        = string

  default     = "Server is running!"#     # Workspace metadata  description = "Optional startup command"

}

#     workspace_name = data.coder_workspace.me.name  type        = string

variable "html_server_info" {

  description = "Server info to display in generated HTML"#     workspace_owner = data.coder_workspace_owner.me.name  default     = ""

  type        = string

  default     = "Server running on port $PORT"#     }

}

#     # Parameters from shared module

variable "html_instructions" {

  description = "Getting started instructions for generated HTML"#     auto_generate_html = data.coder_parameter.auto_generate_html.value# =============================================================================

  type        = string

  default     = ""#     startup_command = var.startup_cmd_value# Setup Script

}

#   }# =============================================================================

variable "pre_server_setup" {

  description = "Optional script to run before starting server (e.g., npm init, install dependencies)"

  type        = string

  default     = ""variable "exposed_ports_list" {# Setup server script

}

  description = "List of ports to expose"output "setup_server_script" {

variable "workspace_name" {

  description = "Workspace name for HTML generation"  type        = list(string)  value = <<-EOT

  type        = string

}}    #!/bin/bash



variable "workspace_owner" {    # Setup Server

  description = "Workspace owner for HTML generation"

  type        = stringvariable "default_server_command" {    set -e

}

  description = "Default command to start the server (e.g., 'python3 -m http.server $PORT')"    

variable "auto_generate_html" {

  description = "Whether to auto-generate index.html"  type        = string    # Export ports computed by Terraform

  type        = string

}}    export PORTS="${join(",", var.exposed_ports_list)}"



variable "startup_command" {    export PORT="${element(var.exposed_ports_list, 0)}"

  description = "Custom startup command (if provided)"

  type        = stringvariable "server_name" {    

}

  description = "Display name of the server (e.g., 'Python 3 HTTP Server')"    echo "[SETUP-SERVER] Configuring workspace server..."

# Output the setup script

output "setup_server_script" {  type        = string    echo "[SETUP-SERVER] Port: $PORT"

  value = <<-EOT

    #!/bin/bash}    

    # Setup Server (${var.server_name})

    set -e    # Navigate to workspace directory (should be created by init-shell module)

    

    # Export ports computed by Terraformvariable "server_log_file" {    cd /home/coder/workspace

    export PORTS="${join(",", var.exposed_ports_list)}"

    export PORT="${element(var.exposed_ports_list, 0)}"  description = "Path to server log file"    

    

    echo "[SETUP-SERVER] Configuring workspace server..."  type        = string    AUTO_HTML="${var.auto_generate_html}"

    echo "[SETUP-SERVER] Port: $PORT"

      default     = "/tmp/server.log"

    # Navigate to workspace directory (should be created by init-shell module)

    cd /home/coder/workspace}    # Auto-generate HTML if enabled

    

    AUTO_HTML="${var.auto_generate_html}"    if [ "$AUTO_HTML" = "true" ]; then



    # Auto-generate HTML if enabledvariable "server_pid_file" {      if [ ! -f index.html ]; then

    if [ "$AUTO_HTML" = "true" ]; then

      if [ ! -f index.html ]; then  description = "Path to server PID file"  echo "[SETUP-SERVER] Creating default index.html..."

  echo "[SETUP-SERVER] Creating default index.html..."

  # Use an unquoted heredoc so shell variables like $PORT expand  type        = string  # Use an unquoted heredoc so shell variables like $PORT expand

  cat <<-HTML > index.html

<!DOCTYPE html>  default     = "/tmp/server.pid"  cat <<-HTML > index.html

<html lang="en">

<head>}<!DOCTYPE html>

    <meta charset="UTF-8">

    <meta name="viewport" content="width=device-width, initial-scale=1.0"><html lang="en">

    <title>Coder Workspace - ${var.workspace_name}</title>

    <style>variable "html_status_message" {<head>

        body {

            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;  description = "Status message to display in generated HTML"    <meta charset="UTF-8">

            max-width: 800px;

            margin: 50px auto;  type        = string    <meta name="viewport" content="width=device-width, initial-scale=1.0">

            padding: 20px;

            line-height: 1.6;  default     = "Server is running!"    <title>Coder Workspace - ${var.workspace_name}</title>

            background: #f5f5f5;

        }}    <style>

        .container {

            background: white;        body {

            padding: 40px;

            border-radius: 8px;variable "html_server_info" {            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;

            box-shadow: 0 2px 4px rgba(0,0,0,0.1);

        }  description = "Server info to display in generated HTML"            max-width: 800px;

        h1 { color: #333; margin-top: 0; }

        .status {   type        = string            margin: 50px auto;

            background: #e8f5e9;

            padding: 15px;  default     = "Server running on port $PORT"            padding: 20px;

            border-radius: 4px;

            border-left: 4px solid #4caf50;}            line-height: 1.6;

            margin: 20px 0;

        }            background: #f5f5f5;

        .info {

            background: #e3f2fd;variable "html_instructions" {        }

            padding: 15px;

            border-radius: 4px;  description = "Getting started instructions for generated HTML"        .container {

            border-left: 4px solid #2196f3;

            margin: 20px 0;  type        = string            background: white;

        }

        code {  default     = ""            padding: 40px;

            background: #f5f5f5;

            padding: 2px 6px;}            border-radius: 8px;

            border-radius: 3px;

            font-family: 'Monaco', 'Courier New', monospace;            box-shadow: 0 2px 4px rgba(0,0,0,0.1);

        }

        pre {variable "pre_server_setup" {        }

            background: #f5f5f5;

            padding: 15px;  description = "Optional script to run before starting server (e.g., npm init, install dependencies)"        h1 { color: #333; margin-top: 0; }

            border-radius: 4px;

            overflow-x: auto;  type        = string        .status { 

        }

        a { color: #1976d2; text-decoration: none; }  default     = ""            background: #e8f5e9;

        a:hover { text-decoration: underline; }

        .footer {}            padding: 15px;

            margin-top: 40px;

            padding-top: 20px;            border-radius: 4px;

            border-top: 1px solid #eee;

            color: #666;variable "workspace_name" {            border-left: 4px solid #4caf50;

            font-size: 14px;

        }  description = "Workspace name for HTML generation"            margin: 20px 0;

    </style>

</head>  type        = string        }

<body>

    <div class="container">}        .info {

    <h1>Workspace: ${var.workspace_name}</h1>

                    background: #e3f2fd;

    <div class="status">

      <strong>Status:</strong> ${var.html_status_message}variable "workspace_owner" {            padding: 15px;

    </div>

          description = "Workspace owner for HTML generation"            border-radius: 4px;

    <div class="info">

      <strong>Currently Serving:</strong><br>  type        = string            border-left: 4px solid #2196f3;

      ${var.html_server_info}

    </div>}            margin: 20px 0;

        

    <h2>Getting Started</h2>        }

        <p>This workspace is running ${var.server_name}.</p>

        variable "auto_generate_html" {        code {

        <pre><code>${var.html_instructions}</code></pre>

          description = "Whether to auto-generate index.html"            background: #f5f5f5;

    <h2>Workspace Info</h2>

    <ul>  type        = string            padding: 2px 6px;

      <li><strong>Owner:</strong> ${var.workspace_owner}</li>

      <li><strong>Port:</strong> $PORT</li>}            border-radius: 3px;

      <li><strong>Server:</strong> ${var.server_name}</li>

    </ul>            font-family: 'Monaco', 'Courier New', monospace;

        

        <div class="footer">variable "startup_command" {        }

            <!-- auto-generated by Coder -->

            <em>This page was auto-generated. Disable in workspace settings if not needed.</em>  description = "Custom startup command (if provided)"        a { color: #1976d2; text-decoration: none; }

        </div>

    </div>  type        = string        a:hover { text-decoration: underline; }

</body>

</html>}        .footer {

HTML

  echo "[SETUP-SERVER] ✓ index.html created"            margin-top: 40px;

      else

        echo "[SETUP-SERVER] ✓ index.html already exists (leaving as-is)"# Output the setup script            padding-top: 20px;

      fi

    fioutput "setup_server_script" {            border-top: 1px solid #eee;

    

    # Run pre-server setup if provided (e.g., npm init, install dependencies)  value = <<-EOT            color: #666;

    ${var.pre_server_setup != "" ? "echo \"[SETUP-SERVER] Running pre-server setup...\"\n${var.pre_server_setup}" : ""}

        #!/bin/bash            font-size: 14px;

    # Check if custom startup command is provided

    STARTUP_CMD="${var.startup_command}"    # Setup Server (${var.server_name})        }

    if [ -n "$STARTUP_CMD" ] && [ "$STARTUP_CMD" != "" ]; then

      echo "[SETUP-SERVER] Running custom startup command..."    set -e    </style>

      echo "[SETUP-SERVER] Command: $STARTUP_CMD"

      nohup bash -c "$STARTUP_CMD" > /tmp/custom-server.log 2>&1 &    </head>

      echo $! > /tmp/custom-server.pid

      sleep 1    # Export ports computed by Terraform<body>

      if ps -p $(cat /tmp/custom-server.pid) > /dev/null 2>&1; then

        echo "[SETUP-SERVER] ✓ Custom command started (PID: $(cat /tmp/custom-server.pid))"    export PORTS="${join(",", var.exposed_ports_list)}"    <div class="container">

      else

        echo "[SETUP-SERVER] ⚠ Custom command may have failed to start"    export PORT="${element(var.exposed_ports_list, 0)}"    <h1>Workspace: ${var.workspace_name}</h1>

        echo "[SETUP-SERVER] Check logs: tail /tmp/custom-server.log"

      fi            

    elif [ "$AUTO_HTML" = "true" ]; then

      # Start default server in background    echo "[SETUP-SERVER] Configuring workspace server..."    <div class="status">

      echo "[SETUP-SERVER] Starting ${var.server_name}..."

      echo "[SETUP-SERVER] Server will be available at http://localhost:$PORT"    echo "[SETUP-SERVER] Port: $PORT"      <strong>Status:</strong> Workspace is running!

      nohup bash -c "${var.default_server_command}" > ${var.server_log_file} 2>&1 &

      echo $! > ${var.server_pid_file}        </div>

      sleep 2

      if ps -p $(cat ${var.server_pid_file}) > /dev/null 2>&1; then    # Navigate to workspace directory (should be created by init-shell module)        

        echo "[SETUP-SERVER] ✓ ${var.server_name} started (PID: $(cat ${var.server_pid_file}))"

      else    cd /home/coder/workspace    <h2>Getting Started</h2>

        echo "[SETUP-SERVER] ⚠ ${var.server_name} may have failed to start"

        echo "[SETUP-SERVER] Check logs: tail ${var.server_log_file}"            <p>This is a default page. Replace <code>index.html</code> with your own content, or start your application:</p>

      fi

    else    AUTO_HTML="${var.auto_generate_html}"        

      echo "[SETUP-SERVER] Auto HTML disabled and no startup command provided; not starting a server."

    fi        <pre><code># Python



    echo ""    # Auto-generate HTML if enabledpython3 -m http.server $PORT

  EOT

}    if [ "$AUTO_HTML" = "true" ]; then


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
