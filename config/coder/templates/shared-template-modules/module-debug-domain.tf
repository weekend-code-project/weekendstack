# =============================================================================
# Debug Domain Parameter - Shows what base_domain is actually set to
# =============================================================================
# This parameter is for debugging only - shows the actual value of var.base_domain
# and allows manual override if needed.

# Note: data.coder_provisioner.me is already declared in main.tf

locals {
  # Try to get base_domain from provisioner tags, fallback to var.base_domain
  provisioner_base_domain = try(data.coder_provisioner.me.tags["base_domain"], var.base_domain)
}

data "coder_parameter" "debug_base_domain" {
  name         = "debug_base_domain"
  display_name = "🔍 Debug: Base Domain"
  description  = <<-DESC
    DEBUG INFO:
    - var.base_domain value: ${var.base_domain}
    - Provisioner tag value: ${local.provisioner_base_domain}
    - TF_VAR_base_domain env var: NOT ACCESSIBLE in Coder provisioner
    - Using provisioner tags instead
    
    Current domain will be used for:
    - Traefik URLs: https://workspace-name.DOMAIN
    - Preview links: https://workspace-name.DOMAIN
  DESC
  type         = "string"
  default      = local.provisioner_base_domain
  mutable      = true
  order        = 1
}

# Export for use by other modules
locals {
  actual_base_domain = data.coder_parameter.debug_base_domain.value
}
