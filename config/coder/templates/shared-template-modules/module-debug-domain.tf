# =============================================================================
# Debug Domain Parameter - Shows what base_domain is actually set to
# =============================================================================
# Since TF_VAR environment variables aren't accessible in Coder's provisioner,
# we use a parameter with a default from var.base_domain (which templates set).

data "coder_parameter" "debug_base_domain" {
  name         = "debug_base_domain"
  display_name = "🔍 Debug: Base Domain"
  description  = <<-DESC
    DEBUG INFO:
    - Template var.base_domain: ${var.base_domain}
    - TF_VAR not accessible in Coder provisioner
    - Using template's default or manual override
    
    Current domain will be used for:
    - Traefik URLs: https://workspace-name.DOMAIN
    - Preview links: https://workspace-name.DOMAIN
    
    **Change this to weekendcodeproject.dev manually**
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
