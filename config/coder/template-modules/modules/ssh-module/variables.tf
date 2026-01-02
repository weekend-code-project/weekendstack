# =============================================================================
# MODULE VARIABLES: SSH Integration
# =============================================================================

variable "workspace_id" {
  description = "UUID of the workspace (for deterministic port selection)"
  type        = string
}

variable "workspace_password" {
  description = "Password for SSH authentication (typically a workspace secret)"
  type        = string
  sensitive   = true
}

variable "ssh_enable_default" {
  description = "Default value for SSH enable parameter"
  type        = bool
  default     = false
}

variable "host_ip" {
  description = "External IP address of the Docker host (for connection instructions)"
  type        = string
  default     = ""
}

variable "workspace_name" {
  description = "Name of the workspace (for SSH config hostname)"
  type        = string
  default     = "workspace"
}
