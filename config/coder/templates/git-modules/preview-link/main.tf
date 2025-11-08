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
# Creates Coder app buttons for accessing the workspace via different methods:
# - Internal: Coder's built-in proxy (localhost through Coder)
# - Traefik: External subdomain routing (workspace-name.domain.com)
# - Custom: User-specified URL
#
# This module is decoupled from server setup logic.

variable "agent_id" {
  description = "Coder agent ID"
  type        = string
}

variable "workspace_name" {
  description = "Workspace name for URL generation"
  type        = string
}

variable "workspace_owner" {
  description = "Workspace owner username"
  type        = string
}

variable "base_domain" {
  description = "Base domain for Traefik routing (e.g., weekendcodeproject.dev)"
  type        = string
  default     = "localhost"
}

variable "exposed_port" {
  description = "Primary exposed port for internal preview"
  type        = string
  default     = "8080"
}

variable "workspace_start_count" {
  description = "Workspace start count for conditional creation"
  type        = number
}

variable "preview_mode" {
  description = "Selected preview mode: internal, traefik, or custom"
  type        = string
  default     = "traefik"
}

variable "custom_preview_url" {
  description = "Custom preview URL (only used when preview_mode is 'custom')"
  type        = string
  default     = ""
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Generate Traefik external URL
  traefik_url = "https://${var.workspace_name}.${var.base_domain}"
  
  # Generate Coder internal URL format
  # Format: https://coder.domain.com/@owner/workspace.branch/apps/preview
  coder_internal_url = "https://coder.${var.base_domain}/@${var.workspace_owner}/${var.workspace_name}.main/apps/preview"
}

# =============================================================================
# Preview Apps (conditional based on mode)
# =============================================================================

# 1. Internal (Coder Proxy) - Uses localhost, proxied through Coder
resource "coder_app" "preview" {
  count        = var.preview_mode == "internal" ? var.workspace_start_count : 0
  agent_id     = var.agent_id
  slug         = "preview"
  display_name = "Preview (Internal)"
  icon         = "/icon/coder.svg"
  url          = "http://localhost:${var.exposed_port}"
  subdomain    = false
  share        = "owner"
  
  healthcheck {
    url       = "http://localhost:${var.exposed_port}"
    interval  = 5
    threshold = 6
  }
}

# 2. Traefik External - Direct external subdomain access
resource "coder_app" "preview_traefik" {
  count        = var.preview_mode == "traefik" ? var.workspace_start_count : 0
  agent_id     = var.agent_id
  slug         = "preview-traefik"
  display_name = "Preview (Traefik)"
  icon         = "/icon/globe.svg"
  url          = local.traefik_url
  external     = true
}

# 3. Custom URL - User-specified external URL
resource "coder_app" "preview_custom" {
  count        = var.preview_mode == "custom" && var.custom_preview_url != "" ? var.workspace_start_count : 0
  agent_id     = var.agent_id
  slug         = "preview-custom"
  display_name = "Preview (Custom)"
  icon         = "/icon/link.svg"
  url          = var.custom_preview_url
  external     = true
}

# =============================================================================
# Outputs
# =============================================================================

output "preview_url" {
  description = "The resolved preview URL based on selected mode"
  value = (
    var.preview_mode == "traefik" ? local.traefik_url :
    var.preview_mode == "custom" ? var.custom_preview_url :
    local.coder_internal_url
  )
}

output "traefik_url" {
  description = "The generated Traefik external URL"
  value       = local.traefik_url
}
