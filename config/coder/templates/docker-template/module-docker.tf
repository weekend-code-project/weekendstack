# =============================================================================
# MODULE: Docker-in-Docker Integration
# =============================================================================
# DESCRIPTION:
#   Provides Docker-in-Docker capability for running containers inside workspaces.
#   Installs Docker Engine, configures daemon, and creates isolated network.
#
# FEATURES:
#   - Full Docker Engine installation via get.docker.com
#   - Registry mirror configuration for faster pulls
#   - Isolated coder-net network for workspace containers
#   - Graceful failure (doesn't break workspace if Docker setup fails)
#
# USAGE:
#   - Set enable_docker=true to install Docker
#   - Docker daemon runs in background with /tmp/dockerd.log
#   - Access via standard 'docker' commands in workspace terminal
#
# IMPORTANT:
#   Module is always loaded (no count) to avoid git resolution errors.
#   Execution is conditional via startup script (see module-agent.tf).
#   This pattern is required for git-based Terraform modules.
# =============================================================================

# Parameters
data "coder_parameter" "enable_docker" {
  name         = "enable_docker"
  display_name = "Enable Docker-in-Docker"
  description  = "Install and run Docker daemon inside the workspace for container development."
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = false
  order        = 30
}

# Module (always loaded, but scripts only run if enabled)
module "docker" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/docker-integration?ref=v0.1.0"
}
