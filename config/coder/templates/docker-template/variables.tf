# =============================================================================
# Environment Variables
# =============================================================================

variable "workspace_dir" {
  description = "Host directory for workspace files"
  type        = string
  default     = ""
  sensitive   = false
}

variable "ssh_key_dir" {
  description = "Host directory for SSH keys"
  type        = string
  default     = ""
  sensitive   = false
}

variable "traefik_auth_dir" {
  description = "Host directory for Traefik auth files"
  type        = string
  default     = ""
  sensitive   = false
}
