# =============================================================================
# Template Variables
# =============================================================================
# These variables are set during template push by the push-template-versioned.sh script

variable "base_domain" {
  description = "Base domain for workspace URLs (injected from .env during push)"
  type        = string
  default     = "localhost"
}
