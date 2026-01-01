# =============================================================================
# Coder Agent - WordPress Template
# =============================================================================

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=PLACEHOLDER"
  
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
    try(module.ssh[0].ssh_copy_script, "# SSH disabled"),
    try(module.ssh[0].ssh_setup_script, ""),
    "",
    "# Traefik Auth Setup",
    try(module.traefik[0].auth_setup_script, ""),
    "",
    "# WordPress Installation",
    module.wordpress.setup_script,
    "",
    "echo '[WORKSPACE] ✅ WordPress workspace ready!'"
  ])
}
