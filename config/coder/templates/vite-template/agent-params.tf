# =============================================================================
# Coder Agent - Minimal Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.

# Collect custom metadata blocks from modules
# This local is referenced by the overlaid metadata-params.tf
locals {
  docker_metadata = try(module.docker[0].metadata_blocks, [])
  ssh_metadata    = try(module.ssh[0].metadata_blocks, [])
  git_metadata    = try(module.git_integration[0].metadata_blocks, [])
  server_metadata = try(module.setup_server[0].metadata_blocks, [])
  
  # Combine all module metadata - add more as modules are added
  all_custom_metadata = concat(
    local.docker_metadata,
    local.ssh_metadata,
    local.git_metadata,
    local.server_metadata,
    try(module.node_tooling.metadata_blocks, [])
  )
}

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  # Required architecture info
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Git identity (using workspace owner info)
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  
  # Access URL for agent connection
  # Use host.docker.internal to ensure the agent can reach Coder via the Docker gateway
  # regardless of host firewall settings or IP changes.
  coder_access_url = "http://host.docker.internal:7080"
  
  # No additional environment variables
  env_vars = {}
  
  # Metadata blocks from metadata module (Issue #27)
  # Now includes custom blocks dynamically contributed by loaded modules
  metadata_blocks = module.metadata.metadata_blocks
  
  # Minimal startup script - just bash basics
  startup_script = join("\n", [
    "#!/bin/bash",
    "echo '[WORKSPACE] Starting workspace ${data.coder_workspace.me.name} (v103)'",
    "",
    "# Phase 1 Module: init-shell (Issue #23)",
    module.init_shell.setup_script,
    "",
    "echo '[DEBUG] Phase 1 complete. Starting Phase 2...'",
    "set +e",
    "",
    "# Phase 2 Module: node-tooling",
    module.node_tooling.tooling_install_script,
    "",
    "echo '[DEBUG] Phase 2 complete.'",
    "",
    "# Git Module: git-identity (always runs)",
    module.git_identity.setup_script,
    "",
    "# Git Module: git-integration (Issue #29) - Conditional clone",
    try(module.git_integration[0].clone_script, "# Git clone disabled"),
    "",
    "# Git Module: Auto-detected CLI (GitHub or Gitea)",
    try(module.github_cli[0].install_script, ""),
    try(module.gitea_cli[0].install_script, ""),
    "echo '[DEBUG] Git CLI complete'",
    "",
    "# Phase 2b Module: node-modules-persistence (AFTER git clone so package.json exists)",
    module.node_modules_persistence.init_script,
    "echo '[DEBUG] Node modules complete'",
    "",
    "# Scaffold new Vite project if no git repo was cloned",
    "cd /home/coder/workspace",
    "if [ ! -f package.json ]; then",
    "  echo '[VITE] No package.json found - scaffolding new Vite + React + TypeScript project...'",
    "  export NVM_DIR=$HOME/.nvm",
    "  [ -s $NVM_DIR/nvm.sh ] && . $NVM_DIR/nvm.sh",
    "  nvm use default >/dev/null 2>&1",
    "  npm create vite@latest . -- --template react-ts --force",
    "  if [ $? -eq 0 ] && [ -f package.json ]; then",
    "    npm install",
    "    echo '[VITE] ✓ New Vite project created and dependencies installed'",
    "  else",
    "    echo '[VITE] ✗ Scaffolding failed - creating minimal package.json'",
    "    cat > package.json << 'PKG_EOF'",
    "{",
    "  \"name\": \"vite-workspace\",",
    "  \"private\": true,",
    "  \"version\": \"0.0.0\",",
    "  \"type\": \"module\",",
    "  \"scripts\": {",
    "    \"dev\": \"vite\",",
    "    \"build\": \"vite build\",",
    "    \"preview\": \"vite preview\"",
    "  },",
    "  \"dependencies\": {",
    "    \"react\": \"^18.3.1\",",
    "    \"react-dom\": \"^18.3.1\"",
    "  },",
    "  \"devDependencies\": {",
    "    \"@vitejs/plugin-react\": \"^4.3.4\",",
    "    \"vite\": \"^5.4.19\"",
    "  }",
    "}",
    "PKG_EOF",
    "    npm install",
    "    mkdir -p src",
    "    cat > src/main.jsx << 'MAIN_EOF'",
    "import React from 'react'",
    "import ReactDOM from 'react-dom/client'",
    "",
    "ReactDOM.createRoot(document.getElementById('root')).render(",
    "  <React.StrictMode>",
    "    <h1>Vite + React Workspace</h1>",
    "  </React.StrictMode>,",
    ")",
    "MAIN_EOF",
    "    cat > index.html << 'HTML_EOF'",
    "<!doctype html>",
    "<html lang=\"en\">",
    "  <head>",
    "    <meta charset=\"UTF-8\" />",
    "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />",
    "    <title>Vite Workspace</title>",
    "  </head>",
    "  <body>",
    "    <div id=\"root\"></div>",
    "    <script type=\"module\" src=\"/src/main.jsx\"></script>",
    "  </body>",
    "</html>",
    "HTML_EOF",
    "    cat > vite.config.js << 'VITE_BASE_EOF'",
    "import { defineConfig } from 'vite'",
    "import react from '@vitejs/plugin-react'",
    "",
    "export default defineConfig({",
    "  plugins: [react()],",
    "})",
    "VITE_BASE_EOF",
    "    echo '[VITE] ✓ Created minimal Vite project'",
    "  fi",
    "else",
    "  echo '[VITE] Using existing project from repository'",
    "fi",
    "",
    "# Phase 3 Module: docker (Issue #26) - Conditional",
    try(module.docker[0].docker_setup_script, "echo '[DOCKER] Disabled'"),
    "echo '[DEBUG] Docker phase complete'",
    "",
    "# Phase 5 Module: ssh (Issue #33) - Conditional",
    try(module.ssh[0].ssh_copy_script, "echo '[SSH] Disabled'"),
    try(module.ssh[0].ssh_setup_script, ""),
    "echo '[DEBUG] SSH phase complete'",
    "",
    "# Traefik Auth Setup (only runs when password is provided)",
    "(",
    "  set +e",
    try(module.traefik[0].auth_setup_script, "  echo '[TRAEFIK] No auth configured'"),
    "  TRAEFIK_EXIT=$?",
    "  set -e",
    "  if [ $TRAEFIK_EXIT -ne 0 ]; then",
    "    echo '[TRAEFIK] Auth setup failed (non-critical, continuing...)'",
    "  fi",
    ")",
    "echo '[DEBUG] Traefik phase complete'",
    "",
    "# Create workspace-specific Vite config with HMR settings (AFTER npm install)",
    "cd /home/coder/workspace",
    "# Detect which plugins are available and create appropriate config",
    "if npm list @vitejs/plugin-react-swc >/dev/null 2>&1 && npm list lovable-tagger >/dev/null 2>&1; then",
    "  # Lovable project with advanced plugins",
    "  cat > vite.config.workspace.js << 'VITE_EOF'",
    "import { defineConfig } from \"vite\";",
    "import react from \"@vitejs/plugin-react-swc\";",
    "import path from \"path\";",
    "import { componentTagger } from \"lovable-tagger\";",
    "",
    "export default defineConfig(({ mode }) => ({",
    "  server: {",
    "    host: \"0.0.0.0\",",
    "    port: 8080,",
    "    strictPort: false,",
    "    hmr: {",
    "      clientPort: 443,",
    "      host: \"${lower(data.coder_workspace.me.name)}.${var.base_domain}\"",
    "    }",
    "  },",
    "  plugins: [react(), mode === \"development\" && componentTagger()].filter(Boolean),",
    "  resolve: {",
    "    alias: {",
    "      \"@\": path.resolve(__dirname, \"./src\"),",
    "    },",
    "  },",
    "}));",
    "VITE_EOF",
    "  echo '[VITE] Created Lovable workspace config with HMR'",
    "else",
    "  # Basic Vite project with standard plugin",
    "  cat > vite.config.workspace.js << 'VITE_EOF'",
    "import { defineConfig } from \"vite\";",
    "import react from \"@vitejs/plugin-react\";",
    "",
    "export default defineConfig({",
    "  server: {",
    "    host: \"0.0.0.0\",",
    "    port: 8080,",
    "    strictPort: false,",
    "    hmr: {",
    "      clientPort: 443,",
    "      host: \"${lower(data.coder_workspace.me.name)}.${var.base_domain}\"",
    "    }",
    "  },",
    "  plugins: [react()],",
    "}));",
    "VITE_EOF",
    "  echo '[VITE] Created basic workspace config with HMR'",
    "fi",
    "",
    "# Start Vite dev server with workspace config",
    "export PORT=$(echo \"$PORTS\" | cut -d',' -f1)",
    "export NVM_DIR=\"$HOME/.nvm\"",
    "[ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"",
    "nvm use default >/dev/null 2>&1",
    "echo '[VITE] Starting Vite dev server on port $PORT...'",
    "exec npx vite --config vite.config.workspace.js",
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
