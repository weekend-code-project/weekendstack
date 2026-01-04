# =============================================================================
# Coder Agent - Test Template Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.
# Updated to work with config-based module system.

# Collect custom metadata blocks from modules
# This local is referenced by the overlaid metadata-params.tf
# Start with empty array for Phase 1, add modules as we test
locals {
  # Phase 1: No custom metadata
  all_custom_metadata = []
  
  # Phase 2+: Uncomment as modules are added
  # docker_metadata = try(module.docker[0].metadata_blocks, [])
  # ssh_metadata    = try(module.ssh[0].metadata_blocks, [])
  # git_metadata    = try(module.git_integration[0].metadata_blocks, [])
  # server_metadata = try(module.setup_server[0].metadata_blocks, [])
  # 
  # all_custom_metadata = concat(
  #   local.docker_metadata,
  #   local.ssh_metadata,
  #   local.git_metadata,
  #   local.server_metadata
  # )
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
  coder_access_url = "http://host.docker.internal:7080"
  
  # No additional environment variables for Phase 1
  env_vars = {}
  
  # Metadata blocks (empty for Phase 1, populated when metadata module added)
  metadata_blocks = []
  
  # Minimal startup script for Phase 1
  # Modules will add their scripts as they're enabled in modules.txt
  startup_script = join("\n", [
    "#!/bin/bash",
    "echo '[WORKSPACE] Starting workspace ${data.coder_workspace.me.name}'",
    "",
    "# Phase 1: init-shell (always included)",
    try(module.init_shell.setup_script, ""),
    "",
    "# Phase 2+: Additional modules (uncomment as added)",
    # try(module.git_identity.setup_script, ""),
    # try(module.git_integration[0].clone_script, ""),
    # try(module.github_cli[0].install_script, ""),
    # try(module.gitea_cli[0].install_script, ""),
    # try(module.docker[0].docker_setup_script, ""),
    # try(module.ssh[0].ssh_copy_script, ""),
    # try(module.ssh[0].ssh_setup_script, ""),
    # try(module.traefik[0].auth_setup_script, ""),
    # try(module.setup_server[0].setup_server_script, ""),
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
