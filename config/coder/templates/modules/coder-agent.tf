# =============================================================================
# MODULE: Coder Agent
# =============================================================================
# DESCRIPTION:
#   Configures the Coder agent that runs inside the workspace container.
#   Composes startup scripts from various modules and sets up Git identity.
#
# DEPENDENCIES:
#   - data.coder_provisioner.me
#   - data.coder_workspace_owner.me
#   - local.init_shell (from init-shell.tf)
#   - local.install_docker (from install-docker.tf)
#   - local.docker_config (from docker-config.tf)
#   - local.traefik_auth_setup (from traefik-auth.tf)
#   - local.setup_server (from setup-server.tf)
#
# OUTPUTS:
#   - coder_agent.main: The agent resource (used by code-server.tf, preview-app.tf)
#
# STARTUP SCRIPT COMPOSITION:
#   Modules are executed in order:
#   1. init-shell: Initialize home directory
#   2. install-docker: Install Docker Engine
#   3. docker-config: Configure Docker-in-Docker daemon
#   4. traefik-auth: Setup authentication (if enabled)
#   5. setup-server: Start default web server
#
# MONITORING:
#   Includes basic resource monitoring metadata:
#   - CPU usage
#   - RAM usage
#   - Home disk usage
#
# =============================================================================

locals {
  # Sentinel to mark completion of all startup modules
  startup_epilogue = <<-EOT
    echo "[STARTUP] ✅ All startup modules executed"
    date | tee /var/tmp/coder_startup_done >/dev/null
  EOT
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # Compose startup script from modules
  # Add new modules here in the order they should execute
  startup_script = join("\n", [
    local.init_shell,
    local.git_identity,
    local.ssh_copy,
    local.install_docker,
    local.docker_config,
    local.ssh_setup,
    local.traefik_auth_setup,
    local.install_github_cli,
    # Clone early so workspace contains repo before setting up node_modules and server
    local.git_clone_if_needed,
    local.install_node,
    local.setup_node_modules_persistence,
    local.setup_server,
    local.validate_workspace,
    local.startup_epilogue,
  ])

  # Git identity configuration
  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    CODER_ACCESS_URL    = var.coder_access_url
    # Expose ports so startup scripts and metadata can reference them
  PORTS               = join(",", local.exposed_ports_list)
  PORT                = element(local.exposed_ports_list, 0)
    SSH_PORT            = local.resolved_ssh_port
    NM_PATHS            = join(",", local.nm_paths)
  }

  # Resource monitoring metadata
  # Resource monitoring metadata — generated from local.metadata_blocks
  dynamic "metadata" {
    for_each = toset(range(length(local.metadata_blocks)))
    content {
      display_name = local.metadata_blocks[metadata.key].display_name
      key          = format("%02d_%s", metadata.key + 1, replace(local.metadata_blocks[metadata.key].display_name, " ", "_"))
      script       = local.metadata_blocks[metadata.key].script
      interval     = local.metadata_blocks[metadata.key].interval
      timeout      = local.metadata_blocks[metadata.key].timeout
    }
  }
}
