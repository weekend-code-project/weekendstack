# =============================================================================
# Setup Server Module (Node/Express) - Local to Node Template  
# =============================================================================
# This module configures the shared setup-server git module with Node/Express-specific
# parameters. The actual server logic is in the shared git module.

# Resolve startup command at Terraform time
locals {
  startup_cmd_value = try(data.coder_parameter.startup_command[0].value, "")
}

# Call the shared setup-server git module with Node-specific configuration
module "setup_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/setup-server?ref=v0.1.1"
  
  # Port configuration
  exposed_ports_list = local.exposed_ports_list
  
  # Node-specific configuration
  default_server_command = "npm run start"
  server_name            = "Express Server"
  server_log_file        = "/tmp/express-server.log"
  server_pid_file        = "/tmp/express-server.pid"
  
  # HTML content for static site
  html_status_message = "Express server is running!"
  html_server_info    = "Node.js Express server on port $PORT"
  html_instructions   = <<-INSTRUCTIONS
    # Create a new Vite app
    npm create vite@latest myapp
    cd myapp
    npm install
    npm run dev -- --port $PORT
    
    # Or run your custom app
    npm start
  INSTRUCTIONS
  
  # Pre-setup: Initialize package.json and install Express
  pre_server_setup = <<-SETUP
    if [ ! -f package.json ]; then npm init -y >/dev/null 2>&1 || true; fi
    if ! npm list express >/dev/null 2>&1; then
      echo "[SETUP-SERVER] Installing express..."
      npm install express >/dev/null 2>&1 || true
    fi
    # Create simple Express server
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
    # Add start script to package.json
    node -e "const fs=require('fs');const p='package.json';const pkg=fs.existsSync(p)?JSON.parse(fs.readFileSync(p)):{};pkg.scripts=pkg.scripts||{};pkg.scripts.start=pkg.scripts.start||'node server.js';fs.writeFileSync(p, JSON.stringify(pkg, null, 2));"
  SETUP
  
  # Workspace metadata
  workspace_name  = data.coder_workspace.me.name
  workspace_owner = data.coder_workspace_owner.me.name
  
  # Parameters from shared template modules
  auto_generate_html = data.coder_parameter.auto_generate_html.value
  startup_command    = local.startup_cmd_value
}

# Export the script for use in agent module
locals {
  setup_server_script = module.setup_server.setup_server_script
}
