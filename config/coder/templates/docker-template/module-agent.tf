# =============================================================================
# MODULE: Coder Agent (Startup Script Orchestrator)
# =============================================================================
# DESCRIPTION:
#   Configures the Coder agent that runs inside the workspace container.
#   Orchestrates all startup scripts from feature modules in the correct order.
#
# STARTUP SEQUENCE:
#   1. init_shell - Initialize home directory structure
#   2. git_identity - Configure Git user.name and user.email
#   3. ssh_copy - Copy SSH keys from host to workspace
#   4. git_integration - Clone repository if configured
#   5. github_cli - Install GitHub CLI if repository cloned
#   6. docker - Install and configure Docker-in-Docker (conditional)
#   7. ssh_setup - Configure and start SSH server (conditional)
#   8. traefik_auth - Setup Traefik authentication (conditional)
#   9. setup_server - Start static site server or custom command
#
# CONDITIONAL EXECUTION:
#   - GitHub CLI: Only if clone_repo=true AND install_github_cli=true
#   - Docker: Only if enable_docker=true
#   - Traefik Auth: Only if make_public=false
#
# PATTERN:
#   Git modules are always loaded (no count), but scripts execute conditionally
#   using ternary operators: condition ? script : ""
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.0"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  depends_on = [
    null_resource.ensure_workspace_folder
  ]
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "set -e",
    "echo '[WORKSPACE] 🚀 Starting workspace ${data.coder_workspace.me.name}'",
    "",
    module.init_shell.setup_script,
    module.git_identity.setup_script,
    module.ssh.ssh_copy_script,
    module.git_integration.clone_script,
    (data.coder_parameter.clone_repo.value && try(data.coder_parameter.install_github_cli[0].value, false)) ? module.github_cli.install_script : "",
    data.coder_parameter.enable_docker.value ? module.docker.docker_install_script : "",
    data.coder_parameter.enable_docker.value ? module.docker.docker_config_script : "",
    module.ssh.ssh_setup_script,
    !data.coder_parameter.make_public.value ? local.traefik_auth_setup_script : "",
    module.setup_server.setup_server_script,
    "",
    "echo '[WORKSPACE] ✅ Workspace ready!'",
    "echo '[WORKSPACE] 🌐 Server URL: http://localhost:8080'",
  ])
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = "http://coder:7080"
  
  env_vars = {
    SSH_PORT = module.ssh.ssh_port
  }
  
  metadata_blocks = module.metadata.metadata_blocks
}
