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
  
  # Combine all module metadata - add more as modules are added
  all_custom_metadata = concat(
    local.docker_metadata,
    local.ssh_metadata,
    local.git_metadata
  )
}

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent?ref=PLACEHOLDER"
  
  # Required architecture info
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Git identity (using workspace owner info)
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  
  # Access URL for agent connection
  coder_access_url = "http://host.docker.internal:7080"
  
  # No additional environment variables
  env_vars = {}
  
  # Metadata blocks from metadata module (Issue #27)
  # Now includes custom blocks dynamically contributed by loaded modules
  metadata_blocks = module.metadata.metadata_blocks
  
  # Minimal startup script - just bash basics
  startup_script = join("\n", [
    "#!/bin/bash",
    "set -e",
    "echo '[WORKSPACE] Starting workspace ${data.coder_workspace.me.name}'",
    "",
    "# Phase 1 Module: init-shell (Issue #23)",
    module.init_shell.setup_script,
    "",
    "# Git Module: git-identity (always runs)",
    module.git_identity.setup_script,
    "",
    "# Git Module: git-integration (Issue #29) - Conditional clone",
    try(module.git_integration[0].clone_script, "# Git clone disabled"),
    "",
    "# Git Module: github-cli (Issue #29) - Conditional GitHub CLI",
    try(module.github_cli[0].install_script, "# GitHub CLI disabled"),
    "",
    "# Phase 3 Module: docker (Issue #26) - Conditional",
    try(module.docker[0].docker_install_script, "# Docker disabled"),
    try(module.docker[0].docker_config_script, ""),
    try(module.docker[0].docker_test_script, ""),
    "",
    "# Phase 5 Module: ssh (Issue #33) - Conditional",
    try(module.ssh[0].ssh_copy_script, "# SSH disabled"),
    try(module.ssh[0].ssh_setup_script, ""),
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
