# =============================================================================
# Template Variables
# =============================================================================
# These variables are set during template push by the push-template-versioned.sh script

variable "base_domain" {
  description = "Base domain for workspace URLs (injected from .env during push)"
  type        = string
  default     = "localhost"
}

variable "host_ip" {
  description = "External IP address of the Docker host VM (for SSH connection instructions)"
  type        = string
  default     = "192.168.1.50"
}
