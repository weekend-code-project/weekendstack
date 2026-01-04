# =============================================================================
# Coder Agent - Minimal Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.

# Collect custom metadata blocks from modules
# This local is referenced by the overlaid metadata-params.tf
# NOTE: Only include ALWAYS-LOADED modules (no count conditional) to prevent evaluation loops
# Conditional modules (git_integration, docker, ssh, setup_server) cannot be safely referenced here
# as they create circular dependencies during parameter preview evaluation
locals {
  # Empty for now - only use built-in metadata picker options
  all_custom_metadata = []  # Empty for now - only use built-in metadata picker options
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
    "# Phase 2b Module: node-modules-persistence",
    module.node_modules_persistence.init_script,
    "",
    "echo '[DEBUG] Phase 2 complete.'",
    "",
    "# Git Module: git-identity (always runs)",
    module.git_identity.setup_script,
    "",
    "# Git Module: git-integration (conditional clone based on parameter)",
    data.coder_parameter.github_repo.value != "" ? module.git_integration.clone_script : "echo '[GIT] No repository URL provided - skipping clone'",
    "",
    "# Git Module: GitHub CLI (conditional based on toggle)",
    data.coder_parameter.install_github_cli.value ? module.github_cli.install_script : "echo '[GIT] GitHub CLI installation disabled'",
    "",
    "# Git Module: Gitea CLI (conditional based on auto-detection)",
    local.use_gitea_cli ? module.gitea_cli.install_script : "echo '[GIT] Gitea CLI not needed for this repository'",
    "",
    "# Phase 3 Module: docker (Issue #26) - Conditional",
    try(module.docker[0].docker_setup_script, "# Docker disabled"),
    "",
    "# Phase 5 Module: ssh (always loaded, runs conditionally based on toggle)",
    module.ssh.ssh_copy_script,
    module.ssh.ssh_setup_script,
    "echo '[DEBUG] SSH phase complete'",
    "",
    "# Traefik Auth Setup (only runs when password is provided)",
    try(module.traefik[0].auth_setup_script, ""),
    "",
    "# Phase 6 Module: setup-server (Issue #32) - Conditional",
    try(module.setup_server[0].setup_server_script, "# Server disabled"),
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
