# =============================================================================
# Coder Agent - Startup Script Orchestrator
# =============================================================================
# This file orchestrates the Coder agent and composes the startup script
# from modules listed in modules.txt. The push script will inject module
# script references at the INJECT_MODULES_HERE marker.
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  # Startup script assembled from module outputs
  # The push script will inject module script references here based on modules.txt
  startup_script = join("\n", [
    module.init_shell.setup_script,
    # INJECT_MODULES_HERE
    try(module.docker[0].docker_setup_script, "# Docker disabled"),
    try(module.docker[0].docker_test_script, ""),
  ])
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = data.coder_workspace.me.access_url
  
  env_vars = {
    WORKSPACE_NAME  = data.coder_workspace.me.name
    WORKSPACE_OWNER = data.coder_workspace_owner.me.name
  }
  
  metadata_blocks = []
}
