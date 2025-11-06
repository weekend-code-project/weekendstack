# =============================================================================
# Environment Variables
# =============================================================================
# These variables are ephemeral and not saved in plan files, allowing them
# to change between plan and apply without causing conflicts.

variable "workspace_dir" {
  description = "Host directory for workspace files"
  type        = string
  default     = ""
  sensitive   = false
  ephemeral   = true
}

variable "ssh_key_dir" {
  description = "Host directory for SSH keys"
  type        = string
  default     = ""
  sensitive   = false
  ephemeral   = true
}

variable "traefik_auth_dir" {
  description = "Host directory for Traefik auth files"
  type        = string
  default     = ""
  sensitive   = false
  ephemeral   = true
}
