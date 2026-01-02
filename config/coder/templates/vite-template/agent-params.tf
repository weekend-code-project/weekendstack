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
    "# Phase 6 Module: setup-server (Issue #32) - Conditional",
    try(module.setup_server[0].setup_server_script, "echo '[SERVER] Disabled'"),
    "echo '[DEBUG] Server phase complete'",
    "",
    "# Start Vite dev server directly (foreground, not backgrounded)",
    "cd /home/coder/workspace",
    "export PORT=$(echo \"$PORTS\" | cut -d',' -f1)",
    "export NVM_DIR=\"$HOME/.nvm\"",
    "[ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"",
    "nvm use default >/dev/null 2>&1",
    "echo '[VITE] Starting Vite dev server on port $PORT...'",
    "exec npm run dev -- --host 0.0.0.0",
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
