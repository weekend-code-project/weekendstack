# =============================================================================
# Traefik Routing Module (v2)
# =============================================================================
# Provides external preview access via Traefik reverse proxy with:
#   - Docker labels for Traefik routing
#   - External preview button through tunnel
#   - Basic auth password protection
#
# When enabled, creates a subdomain route: {workspace}.{domain}
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "agent_id" {
  description = "Coder agent ID for external preview button"
  type        = string
}

variable "workspace_name" {
  description = "Name of the workspace (used for subdomain)"
  type        = string
}

variable "workspace_owner" {
  description = "Owner username (used for basic auth)"
  type        = string
}

variable "workspace_owner_id" {
  description = "Owner ID for Coder metadata labels"
  type        = string
  default     = ""
}

variable "workspace_id" {
  description = "Workspace ID for Coder metadata labels"
  type        = string
  default     = ""
}

variable "base_domain" {
  description = "Base domain for Traefik routing (e.g., example.com)"
  type        = string
}

variable "preview_port" {
  description = "Port the preview server is running on"
  type        = string
  default     = "8080"
}

variable "external_preview_enabled" {
  description = "Whether external preview via Traefik is enabled"
  type        = bool
  default     = true
}

variable "workspace_password" {
  description = "Password for basic auth (required when external preview is enabled)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Workspace subdomain URL
  workspace_url = "https://${lower(var.workspace_name)}.${var.base_domain}"
  
  # Router name (lowercase, safe for Traefik)
  router_name = lower(var.workspace_name)
  
  # Auth middleware name
  auth_middleware = "${local.router_name}-auth"
  
  # Generate bcrypt hash inline using Terraform's bcrypt() function
  # This eliminates the need for htpasswd file generation
  password_hash = var.workspace_password != "" ? bcrypt(var.workspace_password) : ""
  
  # Format for Traefik basicauth: username:password_hash
  # Note: $ must be doubled ($$) in Docker labels for Traefik to read correctly
  auth_user_entry = var.workspace_password != "" ? "${var.workspace_owner}:${replace(local.password_hash, "$", "$$")}" : ""
  
  # ==========================================================================
  # Traefik Labels (only when external preview is enabled)
  # ==========================================================================
  traefik_labels = var.external_preview_enabled ? merge(
    # Coder metadata labels (for container identification)
    {
      "coder.owner"          = var.workspace_owner
      "coder.owner_id"       = var.workspace_owner_id
      "coder.workspace_id"   = var.workspace_id
      "coder.workspace_name" = var.workspace_name
    },
    # Base routing labels
    {
      "traefik.enable"         = "true"
      "traefik.docker.network" = "coder-network"
      
      # HTTPS Router (external access via tunnel)
      "traefik.http.routers.${local.router_name}.rule"        = "Host(`${lower(var.workspace_name)}.${var.base_domain}`)"
      "traefik.http.routers.${local.router_name}.entrypoints" = "websecure"
      "traefik.http.routers.${local.router_name}.tls"         = "true"
      "traefik.http.routers.${local.router_name}.service"     = local.router_name
      
      # HTTP Router (local .lab access)
      "traefik.http.routers.${local.router_name}-http.rule"        = "Host(`${lower(var.workspace_name)}.lab`)"
      "traefik.http.routers.${local.router_name}-http.entrypoints" = "web"
      "traefik.http.routers.${local.router_name}-http.service"     = local.router_name
      
      # Service configuration
      "traefik.http.services.${local.router_name}.loadbalancer.server.port" = var.preview_port
    },
    # Auth middleware labels (when password is set) - uses inline bcrypt hash
    var.workspace_password != "" ? {
      "traefik.http.routers.${local.router_name}.middlewares"            = local.auth_middleware
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.users" = local.auth_user_entry
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.realm" = "${var.workspace_owner}-workspace"
    } : {}
  ) : {}
}

# =============================================================================
# External Preview Button
# =============================================================================

resource "coder_app" "external_preview" {
  count = var.external_preview_enabled ? 1 : 0
  
  agent_id     = var.agent_id
  slug         = "external-preview"
  display_name = "External Preview"
  icon         = "/icon/globe.svg"
  url          = local.workspace_url
  external     = true
  order        = 11
}

# =============================================================================
# Outputs
# =============================================================================

output "traefik_labels" {
  description = "Docker labels to apply to workspace container for Traefik routing"
  value       = local.traefik_labels
}

output "workspace_url" {
  description = "External URL for the workspace"
  value       = var.external_preview_enabled ? local.workspace_url : ""
}

output "auth_enabled" {
  description = "Whether basic auth is enabled"
  value       = var.external_preview_enabled && var.workspace_password != ""
}
