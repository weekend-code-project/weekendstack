# =============================================================================
# MODULE: Coder Agent (Startup Script Orchestrator)
# =============================================================================
# DESCRIPTION:
#   Configures the Coder agent that runs inside the workspace container.
#   Orchestrates all startup scripts from feature modules in the correct order.
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=v0.1.2-test-base"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  depends_on = [
    null_resource.ensure_workspace_folder
  ]
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "# Note: No set -e here - modules handle their own errors",
    "echo '[WORKSPACE] 🚀 Starting workspace ${data.coder_workspace.me.name}'",
    "",
    module.init_shell.setup_script,
    module.git_identity.setup_script,
    module.ssh.ssh_copy_script,
    module.git_integration.clone_script,
    (data.coder_parameter.clone_repo.value && try(data.coder_parameter.install_github_cli.value, false)) ? module.github_cli.install_script : "",
    data.coder_parameter.enable_docker.value ? module.docker.docker_setup_script : "",
    module.ssh.ssh_setup_script,
    local.traefik_auth_setup_script,
    local.setup_server_script,
  "",
  "echo '[WORKSPACE] ✅ Workspace ready!'",
  "echo '[WORKSPACE] 🌐 Server URL: http://localhost:8080'",
  ])
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = "http://coder:7080"
  
  env_vars = {
    SSH_PORT = module.ssh.ssh_port
    PORTS    = join(",", local.exposed_ports_list)
    PORT     = element(local.exposed_ports_list, 0)
  }
  
  metadata_blocks = module.metadata.metadata_blocks
}
