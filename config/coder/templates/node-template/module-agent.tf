module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/coder-agent?ref=v0.1.0"
  arch   = data.coder_provisioner.me.arch
  os     = "linux"

  depends_on = [
    null_resource.ensure_workspace_folder
  ]

  startup_script = join("\n", [
    "#!/bin/bash",
    "set -e",
    "echo '[WORKSPACE] 🚀 Starting Node workspace ${data.coder_workspace.me.name}'",
    "",
    module.init_shell.setup_script,
    module.git_identity.setup_script,
    module.ssh.ssh_copy_script,
    module.git_integration.clone_script,
    (data.coder_parameter.clone_repo.value && try(data.coder_parameter.install_github_cli[0].value, false)) ? module.github_cli.install_script : "",
  data.coder_parameter.node_install_strategy.value != "system" || data.coder_parameter.node_version.value != "" ? module.node_version.node_setup_script : "",
  module.node_tooling.tooling_install_script,
    module.node_modules_persistence.init_script,
    data.coder_parameter.enable_docker.value ? module.docker.docker_install_script : "",
    data.coder_parameter.enable_docker.value ? module.docker.docker_config_script : "",
    module.ssh.ssh_setup_script,
  !data.coder_parameter.make_public.value ? local.traefik_auth_setup_script : "",
  local.setup_server_script,
    "",
    "echo '[WORKSPACE] ✅ Node workspace ready!'",
    "echo '[WORKSPACE] 🌐 Server URL: http://localhost:${element(local.exposed_ports_list, 0)}'",
  ])

  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  coder_access_url = "http://coder:7080"

  env_vars = merge(
    module.node_modules_persistence.env,
    {
      SSH_PORT = module.ssh.ssh_port
      PORTS    = join(",", local.exposed_ports_list)
      PORT     = element(local.exposed_ports_list, 0)
    }
  )

  metadata_blocks = module.metadata.metadata_blocks
}
