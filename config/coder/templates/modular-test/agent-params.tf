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
    module.git_identity.setup_script,
    try(module.git_integration[0].clone_script, ""),
    try(module.github_cli[0].install_script, ""),
    try(module.gitea_cli[0].install_script, ""),
    try(module.docker[0].docker_setup_script, "# Docker disabled"),
    try(module.docker[0].docker_test_script, ""),
    try(module.ssh[0].ssh_copy_script, ""),
    try(module.ssh[0].ssh_setup_script, ""),
    try(module.traefik[0].auth_setup_script, ""),
    try(module.setup_server.setup_server_script, ""),  # Run last - starts server
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
