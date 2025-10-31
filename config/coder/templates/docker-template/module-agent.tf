# =============================================================================
# MODULE: Coder Agent
# =============================================================================
# Core agent that runs inside the workspace container
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
    # module.docker.docker_install_script,
    # module.docker.docker_config_script,
    module.ssh.ssh_setup_script,
    # module.traefik_auth.traefik_auth_setup_script,
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
