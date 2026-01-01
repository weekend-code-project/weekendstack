# =============================================================================
# Docker Parameters (Vite Template Override)
# =============================================================================
# OVERRIDE NOTE: This file overrides the shared docker-params.tf
# to disable Docker by default (Vite projects don't typically need Docker)

data "coder_parameter" "enable_docker" {
  name         = "enable_docker"
  display_name = "Enable Docker"
  description  = "Install and run Docker-in-Docker (disabled by default for Vite)"
  type         = "bool"
  form_type    = "switch"
  default      = "false"
  mutable      = true
  order        = 30
}

# Module integration - conditional on parameter
module "docker" {
  count  = data.coder_parameter.enable_docker.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/docker-module?ref=PLACEHOLDER"
}
