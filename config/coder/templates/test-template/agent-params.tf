# =============================================================================
# Coder Agent - Minimal Configuration
# =============================================================================
# This creates the Coder agent that runs inside the workspace container.

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
    "# Phase 3 Module: docker (Issue #26) - Conditional",
    try(module.docker[0].docker_install_script, "# Docker disabled"),
    try(module.docker[0].docker_config_script, ""),
    try(module.docker[0].docker_test_script, ""),
    "",
    "echo '[WORKSPACE] Workspace ready!'"
  ])
}
