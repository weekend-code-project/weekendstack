# =============================================================================
# Traefik Routing Module (v2)
# =============================================================================
# Provides external preview access via Traefik reverse proxy with:
#   - Docker labels for Traefik routing
#   - External preview button through tunnel
#   - Basic auth password protection (bcrypt hash computed at provision time)
#
# Auth is set via inline `basicauth.users` label using Terraform's bcrypt().
# This avoids the usersFile approach which requires a shared host bind-mount
# that Traefik can't see (it reads its own container FS, not the workspace's).
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
  description = "Password for basic auth protection on external preview (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "host_ip" {
  description = "Host IP address (used for local preview URL when tunnel is disabled)"
  type        = string
  default     = "127.0.0.1"
}

variable "access_url" {
  description = "Coder access URL (used to detect tunnel vs local access)"
  type        = string
  default     = "http://localhost:7080"
}

variable "create_preview_app" {
  description = "Whether to create the external preview app button (disable if template creates its own)"
  type        = bool
  default     = true
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Detect tunnel by checking if access_url uses HTTPS (tunnel terminates SSL)
  tunnel_enabled = startswith(var.access_url, "https://")

  # Workspace subdomain URL - tunnel uses HTTPS domain, local uses HTTP IP
  workspace_url = local.tunnel_enabled ? "https://${lower(var.workspace_name)}.${var.base_domain}" : "http://${lower(var.workspace_name)}.${var.host_ip}.nip.io"
  
  # Router name (lowercase, safe for Traefik)
  router_name = lower(var.workspace_name)
  
  # Auth middleware name
  auth_middleware = "${local.router_name}-auth"

  # bcrypt hash of the password computed at provision time.
  # Labels are set via the Terraform Docker provider (Docker API), NOT Docker Compose,
  # so dollar signs must NOT be doubled — they are stored as-is in container labels.
  # bcrypt() returns a new hash each apply, but the password validation still works.
  auth_users_label = var.workspace_password != "" ? "${var.workspace_owner}:${bcrypt(var.workspace_password)}" : ""
  
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
    # Auth middleware labels (when password is set).
    # Uses inline bcrypt hash — no shared volume or runtime htpasswd script needed.
    var.workspace_password != "" ? {
      "traefik.http.routers.${local.router_name}.middlewares"               = local.auth_middleware
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.users"   = local.auth_users_label
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.realm"   = "${var.workspace_owner}-workspace"
    } : {}
  ) : {}
}

# =============================================================================
# External Preview Button
# =============================================================================

resource "coder_app" "external_preview" {
  count = var.external_preview_enabled && var.create_preview_app ? 1 : 0
  
  agent_id     = var.agent_id
  slug         = "external-preview"
  display_name = "External Preview"
  icon         = "/icon/desktop.svg"
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
