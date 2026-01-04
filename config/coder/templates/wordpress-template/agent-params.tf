# =============================================================================
# Coder Agent - WordPress Template
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=v0.1.0"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  
  coder_access_url = "http://host.docker.internal:7080"
  
  env_vars = {}
  
  metadata_blocks = []
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "echo '[WORKSPACE] 🚀 Starting WordPress workspace ${data.coder_workspace.me.name}'",
    "",
    "# SSH Setup",
    local.ssh_copy_script,
    local.ssh_setup_script,
    "",
    "# Traefik Auth Setup",
    local.traefik_auth_setup_script,
    "",
    "# WordPress Installation",
    local.wordpress_install_script,
    "",
    "echo '[WORKSPACE] ✅ WordPress workspace ready!'"
  ])
}
