# =============================================================================
# BASE TEMPLATE VARIABLES
# =============================================================================
# These variables are substituted at push time by the push-template.sh script.
# =============================================================================

variable "base_domain" {
  type        = string
  description = "Base domain for workspace routing (e.g., example.com)"
  default     = "localhost"
}

variable "host_ip" {
  type        = string
  description = "Host IP address for port mappings"
  default     = "127.0.0.1"
}

variable "traefik_auth_dir" {
  type        = string
  description = "Host directory for Traefik auth files (htpasswd)"
  default     = "/opt/stacks/traefik/auth"
}
