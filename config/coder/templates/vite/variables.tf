# =============================================================================
# VITE TEMPLATE VARIABLES
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

variable "gitlab_host" {
  type        = string
  description = "Self-hosted GitLab hostname (e.g. git.example.com). Empty = gitlab.com."
  default     = ""
}

variable "github_external_auth" {
  type        = bool
  description = "Whether GitHub External Auth is configured on the Coder server"
  default     = false
}
