# =============================================================================
# Setup Server Parameters
# =============================================================================
# Parameters for configuring a development server in the workspace.
# Inlined script to bypass module loading issues.

# =============================================================================
# Parameters
# =============================================================================

data "coder_parameter" "startup_command" {
  name         = "startup_command"
  display_name = "Server Startup Command"
  description  = "Command to run server at startup (defaults to Python HTTP server)"
  type         = "string"
  default      = "python3 -m http.server 8080 --bind 0.0.0.0"
  mutable      = true
  order        = 20
}

data "coder_parameter" "generate_html" {
  name         = "generate_html"
  display_name = "Generate Landing Page"
  description  = "Auto-generate index.html if it doesn't exist"
  type         = "bool"
  form_type    = "switch"
  default      = "true"
  mutable      = true
  order        = 21
}

data "coder_parameter" "num_ports" {
  name         = "num_ports"
  display_name = "Number of Ports"
  description  = "Number of ports to expose (8080-8089)"
  type         = "number"
  form_type    = "slider"
  default      = 1
  mutable      = true
  order        = 22
  
  validation {
    min = 1
    max = 10
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Generate list of internal ports: [8080, 8081, 8082, ...]
  num_ports_value = data.coder_parameter.num_ports.value
  exposed_ports_list = [
    for i in range(local.num_ports_value) : tostring(8080 + i)
  ]
  
  # Server configuration
  startup_command    = trimspace(data.coder_parameter.startup_command.value)
  auto_generate_html = data.coder_parameter.generate_html.value
  has_server_config  = local.startup_command != ""  # Only run server if command provided
}

# =============================================================================
# Inline Setup Server Script (bypasses module loading)
# =============================================================================

locals {
  setup_server_script = <<-EOT
    #!/bin/bash
    set -e
    
    echo "[SETUP-SERVER] ==================== MODULE LOADED ===================="
    echo "[SETUP-SERVER] 🔧 Starting setup..."
    
    cd /home/coder/workspace
    echo "[SETUP-SERVER] 📂 Workspace: $(pwd)"
    
    AUTO_HTML="${local.auto_generate_html}"
    echo "[SETUP-SERVER] 🎨 Generate HTML: $AUTO_HTML"
    
    if [ "$AUTO_HTML" = "true" ]; then
        echo "[SETUP-SERVER] ✍️ Generating index.html..."
        cat > index.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>IT WORKS!</title>
    <style>
        body {
            font-family: system-ui, -apple-system, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        h1 {
            font-size: 4rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
    </style>
</head>
<body>
    <h1>🎉 IT WORKS! 🎉</h1>
</body>
</html>
HTML
        echo "[SETUP-SERVER] ✅ Generated index.html ($(wc -c < index.html) bytes)"
        ls -lh index.html
    fi
    
    echo "[SETUP-SERVER] 🏁 Complete!"
  EOT
}
