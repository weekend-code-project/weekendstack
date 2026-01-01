# =============================================================================
# Coder Agent - WordPress Configuration
# =============================================================================

# Collect custom metadata blocks from modules
locals {
  ssh_metadata    = try(module.ssh[0].metadata_blocks, [])
  
  all_custom_metadata = concat(
    local.ssh_metadata,
    try(module.wordpress.metadata_blocks, [])
  )
}

module "agent" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/coder-agent-module?ref=feature/services-cleanup"
  
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
  
  coder_access_url = "http://host.docker.internal:7080"
  
  env_vars = {
    DB_PASSWORD = random_password.db_password.result
    DB_HOST     = "mysql-${data.coder_workspace.me.name}"
    PHP_VERSION = data.coder_parameter.php_version.value
    WP_URL      = "https://${lower(data.coder_workspace.me.name)}.${var.base_domain}"
  }
  
  metadata_blocks = module.metadata.metadata_blocks
  
  startup_script = join("\n", [
    "#!/bin/bash",
    "echo '[WORKSPACE] Starting WordPress workspace ${data.coder_workspace.me.name}'",
    "",
    "# Phase 1: Shell initialization",
    module.init_shell.setup_script,
    "",
    "set +e",
    "",
    "# Phase 2: WordPress setup",
    module.wordpress.setup_script,
    "",
    "# Git Module: git-identity (always runs)",
    module.git_identity.setup_script,
    "",
    "# SSH Module - Conditional",
    try(module.ssh[0].ssh_copy_script, "# SSH disabled"),
    try(module.ssh[0].ssh_setup_script, ""),
    "",
    "# Traefik Auth Setup",
    try(module.traefik[0].auth_setup_script, ""),
    "",
    "echo '[WORKSPACE] WordPress ready! Visit: https://${lower(data.coder_workspace.me.name)}.${var.base_domain}'"
  ])
}
