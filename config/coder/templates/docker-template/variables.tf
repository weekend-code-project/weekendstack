# =============================================================================
# Environment Variables
# =============================================================================
# These are set via TF_VAR_* environment variables in the Coder container.
# Make sure .env file uses absolute paths for Docker bind mounts.

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

variable "base_domain" {
  description = "Base domain for workspace URLs (provided via TF_VAR_base_domain)"
  type        = string
  default     = ""
  nullable    = false
  sensitive   = false
  ephemeral   = true
}
