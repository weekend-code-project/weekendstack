# =============================================================================
# Base Domain - No UI parameter, just use the variable default
# =============================================================================
# The base_domain is set via the template's variables.tf default value,
# which is automatically injected during template push from .env BASE_DOMAIN

# Export for use by other modules
locals {
  actual_base_domain = var.base_domain
}
