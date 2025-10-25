terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# =============================================================================
# Preview Link Module
# =============================================================================
# Creates a Coder app that provides a clickable link to the workspace's
# external URL via Traefik proxy or a custom URL.

variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "workspace_url" {
  description = "External Traefik URL for the workspace (used as default)"
  type        = string
}

variable "workspace_start_count" {
  description = "Workspace start count for conditional creation"
  type        = number
}

variable "use_custom_url" {
  description = "Whether to use a custom URL instead of auto-generated Traefik URL"
  type        = bool
  default     = false
}

variable "custom_url" {
  description = "Custom URL (only used when use_custom_url is true)"
  type        = string
  default     = ""
}

# Determine which URL to use
locals {
  preview_url = var.use_custom_url ? var.custom_url : var.workspace_url
}

# Preview link app (external Traefik URL or custom)
resource "coder_app" "preview_link" {
  count        = var.workspace_start_count
  agent_id     = var.agent_id
  slug         = "preview-link"
  display_name = "External URL"
  url          = local.preview_url
  icon         = "/icon/desktop.svg"
  external     = true
}
