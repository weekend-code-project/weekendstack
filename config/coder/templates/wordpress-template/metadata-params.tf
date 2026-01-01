# =============================================================================
# Metadata Parameters - WordPress Override
# =============================================================================
# WordPress template uses basic metadata without custom selection

# Module: metadata (workspace monitoring)
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata-module?ref=feature/services-cleanup"
  
  enabled_blocks = ["cpu", "ram", "disk"]  # Basic monitoring for WordPress
  custom_blocks  = local.all_custom_metadata
}
