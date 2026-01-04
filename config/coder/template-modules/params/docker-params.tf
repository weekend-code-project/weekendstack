# =============================================================================
# Docker-in-Docker Module
# =============================================================================
# DESCRIPTION:
#   Provides Docker daemon inside workspace containers for container development.
#   Includes installation, configuration, and validation tests.
#
# PARAMETERS:
#   - enable_docker: Boolean toggle to enable/disable Docker-in-Docker
#
# DEPENDENCIES:
#   - git-modules/docker-integration: Core Docker installation and config scripts
#
# OUTPUTS (via module.docker[0] when enabled):
#   - docker_install_script: Install Docker engine
#   - docker_config_script: Configure daemon and start dockerd
#   - docker_test_script: Minimal validation tests
#
# USAGE IN AGENT STARTUP SCRIPT:
#   try(module.docker[0].docker_install_script, "# Docker disabled"),
#   try(module.docker[0].docker_config_script, ""),
#   try(module.docker[0].docker_test_script, ""),
#
# NOTES:
#   - Requires workspace container to run with privileged = true
#   - Uses count-based conditional loading (module.docker[0] when enabled)
#   - Safe access via try() function prevents errors when disabled
# =============================================================================

# Parameter: Enable Docker-in-Docker
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

# Module: Docker Integration (conditionally loaded)
module "docker" {
  count  = data.coder_parameter.enable_docker.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/docker-module?ref=PLACEHOLDER"
}
