# =============================================================================
# Coder Agent - Startup Script Orchestrator
# =============================================================================
# This file orchestrates the Coder agent and composes the startup script
# from modules listed in modules.txt. The push script will inject module
# script references at the INJECT_MODULES_HERE marker.
# =============================================================================

locals {
  hardcoded_index_script = <<-BASH
#!/bin/bash
set -e
echo "[SETUP-SERVER] ==================== STARTING ===================="
cd /home/coder/workspace
echo "[SETUP-SERVER] Creating index.html in $(pwd)"
cat > index.html << 'EOF'
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
        h1 { font-size: 4rem; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
    </style>
</head>
<body>
    <h1>🎉 IT WORKS! 🎉</h1>
</body>
</html>
EOF
echo "[SETUP-SERVER] ✅ Created index.html ($(wc -c < index.html) bytes)"
ls -lh index.html
echo "[SETUP-SERVER] ==================== COMPLETE ===================="
BASH
}

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Startup script assembled from module outputs
  # The push script will inject module script references here based on modules.txt
  startup_script = join("\n", [
    module.init_shell.setup_script,
    # INJECT_MODULES_HERE
    module.git_identity.setup_script,
    try(module.git_integration[0].clone_script, ""),
    try(module.github_cli[0].install_script, ""),
    try(module.gitea_cli[0].install_script, ""),
    try(module.docker[0].docker_setup_script, "# Docker disabled"),
    try(module.docker[0].docker_test_script, ""),
    try(module.ssh[0].ssh_copy_script, ""),
    try(module.ssh[0].ssh_setup_script, ""),
    "echo '[AGENT] About to run traefik auth script...'",
    try(module.traefik[0].auth_setup_script, ""),
    "echo '[AGENT] About to run setup-server script...'",
    local.hardcoded_index_script,
  ])
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = data.coder_workspace.me.access_url
  
  metadata_blocks = module.metadata.metadata_blocks
  
  env_vars = {
    WORKSPACE_NAME  = data.coder_workspace.me.name
    WORKSPACE_OWNER = data.coder_workspace_owner.me.name
  }
}
