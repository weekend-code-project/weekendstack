# =============================================================================
# Traefik Routing Module
# =============================================================================
# Provides Docker labels for Traefik routing configuration

variable "workspace_name" {
  description = "Name of the workspace"
  type        = string
}

variable "workspace_owner" {
  description = "Owner username"
  type        = string
}

variable "workspace_id" {
  description = "Workspace ID"
  type        = string
}

variable "workspace_owner_id" {
  description = "Owner ID"
  type        = string
}

variable "make_public" {
  description = "Whether workspace is public (no auth)"
  type        = bool
}

variable "exposed_ports_list" {
  description = "List of exposed ports"
  type        = list(string)
}

variable "domain" {
  description = "Domain for workspace URL"
  type        = string
  default     = "weekendcodeproject.dev"
}

# Workspace URL
locals {
  workspace_url = "https://${lower(var.workspace_name)}.${var.domain}"
}

# Base Traefik labels (always applied)
locals {
  traefik_base_labels = {
    "coder.owner"          = var.workspace_owner
    "coder.owner_id"       = var.workspace_owner_id
    "coder.workspace_id"   = var.workspace_id
    "coder.workspace_name" = var.workspace_name
    
    # Enable Traefik routing
    "traefik.enable" = "true"
    "traefik.docker.network" = "coder-network"
    
    # Router configuration
    "traefik.http.routers.${lower(var.workspace_name)}.rule" = "Host(`${lower(var.workspace_name)}.${var.domain}`)"
    "traefik.http.routers.${lower(var.workspace_name)}.entrypoints" = "websecure"
    "traefik.http.routers.${lower(var.workspace_name)}.tls" = "true"
    
    # Service configuration (use first port from exposed_ports)
    "traefik.http.services.${lower(var.workspace_name)}.loadbalancer.server.port" = element(var.exposed_ports_list, 0)
  }
}

# Authentication labels (only when workspace is not public)
locals {
  traefik_auth_labels = {
    # Attach auth middleware to router
    "traefik.http.routers.${lower(var.workspace_name)}.middlewares" = "${lower(var.workspace_name)}-auth"
    
    # Middleware references the htpasswd file created by traefik-auth module
    "traefik.http.middlewares.${lower(var.workspace_name)}-auth.basicauth.usersfile" = "/traefik-auth/hashed_password-${var.workspace_name}"
  }
}

# Combined labels - conditionally include auth labels
locals {
  traefik_labels = !var.make_public ? merge(
    local.traefik_base_labels,
    local.traefik_auth_labels
  ) : local.traefik_base_labels
}

# Outputs
output "traefik_labels" {
  description = "Map of Traefik Docker labels"
  value       = local.traefik_labels
}

output "workspace_url" {
  description = "External workspace URL"
  value       = local.workspace_url
}
