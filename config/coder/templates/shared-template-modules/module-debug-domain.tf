# =============================================================================
# Debug Domain Parameter - Shows what base_domain is actually set to
# =============================================================================
# Since TF_VAR environment variables aren't accessible in Coder's provisioner,
# we use a parameter with a default from var.base_domain (which templates set).

data "coder_parameter" "debug_base_domain" {
  name         = "debug_base_domain"
  display_name = "Base Domain Override"
  description  = <<-DESC
    The base domain for workspace URLs is: **${var.base_domain}**
    
    Leave this field as-is to use the configured domain, or override it manually if needed.
    
    This will be used for:
    - Traefik URLs: `https://${data.coder_workspace.me.name}.${var.base_domain}`
    - Preview links: `https://${data.coder_workspace.me.name}.${var.base_domain}`
  DESC
  type         = "string"
  default      = var.base_domain
  mutable      = true
  order        = 1
}

# Export for use by other modules
locals {
  actual_base_domain = data.coder_parameter.debug_base_domain.value
}
