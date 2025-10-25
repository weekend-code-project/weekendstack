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

variable "ssh_port_default" {
  description = "Default SSH port value"
  type        = string
  default     = ""
}

variable "ssh_port_mode_default" {
  description = "Default SSH port mode (manual or auto)"
  type        = string
  default     = "manual"
}
