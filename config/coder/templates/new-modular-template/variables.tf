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
  description = "Host directory path for Traefik auth files (mounted to /traefik-auth in container)"
  default     = "/home/ubuntu/weekendstack/config/traefik/auth"
}

variable "github_external_auth" {
  type        = bool
  description = "Whether GitHub External Auth is configured on the Coder server (enables OAuth token for private repos)"
  default     = false
}