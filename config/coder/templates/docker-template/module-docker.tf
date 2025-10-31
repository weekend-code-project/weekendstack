# =============================================================================
# MODULE: Docker Integration
# =============================================================================
# Provides Docker-in-Docker capability for running containers inside workspaces
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
