# =============================================================================
# Traefik Routing Module
# =============================================================================
# Provides Traefik routing labels and preview buttons for workspace access
# Supports both internal Coder proxy and external Traefik subdomain routing

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">=2.4.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "agent_id" {
  description = "Coder agent ID for preview buttons"
  type        = string
}

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

variable "workspace_start_count" {
  description = "Workspace start count for conditional preview button creation"
  type        = number
}

variable "make_public" {
  description = "Whether workspace is public (no auth required)"
  type        = bool
  default     = true
}

variable "workspace_secret" {
  description = "Password for workspace auth (required when make_public is false)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "exposed_port" {
  description = "Primary exposed port for routing"
  type        = string
  default     = "8080"
}

variable "domain" {
  description = "Base domain for Traefik routing (e.g., example.com)"
  type        = string
}

variable "preview_mode" {
  description = "Preview mode: 'internal' for Coder proxy, 'traefik' for external subdomain"
  type        = string
  default     = "traefik"
  
  validation {
    condition     = contains(["internal", "traefik"], var.preview_mode)
    error_message = "Preview mode must be 'internal' or 'traefik'"
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Workspace URL
  workspace_url = "https://${lower(var.workspace_name)}.${var.domain}"
  
  # Base Traefik labels (always applied when using traefik mode)
  traefik_base_labels = {
    "coder.owner"          = var.workspace_owner
    "coder.owner_id"       = var.workspace_owner_id
    "coder.workspace_id"   = var.workspace_id
    "coder.workspace_name" = var.workspace_name
    
    # Enable Traefik routing
    "traefik.enable"         = "true"
    "traefik.docker.network" = "coder-network"
    
    # Router configuration
    "traefik.http.routers.${lower(var.workspace_name)}.rule"        = "Host(`${lower(var.workspace_name)}.${var.domain}`)"
    "traefik.http.routers.${lower(var.workspace_name)}.entrypoints" = "websecure"
    "traefik.http.routers.${lower(var.workspace_name)}.tls"         = "true"
    
    # Service configuration (use exposed port)
    "traefik.http.services.${lower(var.workspace_name)}.loadbalancer.server.port" = var.exposed_port
  }
  
  # Authentication labels (only when workspace is not public)
  traefik_auth_labels = {
    # Attach auth middleware to router
    "traefik.http.routers.${lower(var.workspace_name)}.middlewares" = "${lower(var.workspace_name)}-auth"
    
    # Middleware references the htpasswd file created by auth setup script
    "traefik.http.middlewares.${lower(var.workspace_name)}-auth.basicauth.usersfile" = "/traefik-auth/hashed_password-${var.workspace_name}"
  }
  
  # Combined Traefik labels - conditionally include auth labels
  traefik_labels = var.preview_mode == "traefik" ? (
    !var.make_public ? merge(local.traefik_base_labels, local.traefik_auth_labels) : local.traefik_base_labels
  ) : {}
  
  # Auth setup script (only runs when not public)
  traefik_auth_enabled = var.preview_mode == "traefik" && !var.make_public
  
  traefik_auth_setup_script = (
    local.traefik_auth_enabled 
    ? <<-EOT
#!/bin/bash
set -e

WORKSPACE_NAME="${var.workspace_name}"
USERNAME="${var.workspace_owner}"

# Check if traefik-auth directory is mounted
if [ ! -d "/traefik-auth" ]; then
  echo "[TRAEFIK-AUTH] ✗ /traefik-auth directory not mounted; skipping auth setup"
  exit 0
fi

# Install htpasswd if not available
if ! command -v htpasswd >/dev/null 2>&1; then
  echo "[TRAEFIK-AUTH] Installing apache2-utils..."
  sudo apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y -qq apache2-utils >/dev/null 2>&1
fi

# Set permissions
sudo chown -R coder:coder /traefik-auth 2>/dev/null || true

# Validate password provided
SECRET_VALUE="${var.workspace_secret}"
if [ -z "$SECRET_VALUE" ]; then
  echo "[TRAEFIK-AUTH] ✗ Password required for private workspace"
  exit 1
fi

# Generate htpasswd file
echo "[TRAEFIK-AUTH] Setting up basic auth for workspace..."
htpasswd -nbB "$USERNAME" "$SECRET_VALUE" | sudo tee "/traefik-auth/hashed_password-$WORKSPACE_NAME" >/dev/null
sudo chmod 600 "/traefik-auth/hashed_password-$WORKSPACE_NAME"

# Create dynamic Traefik config
sudo tee "/traefik-auth/dynamic-$WORKSPACE_NAME.yaml" >/dev/null <<EOF
http:
  middlewares:
    $(echo "$WORKSPACE_NAME" | tr '[:upper:]' '[:lower:]')-auth:
      basicAuth:
        realm: "$USERNAME-$WORKSPACE_NAME-workspace"
        usersFile: "/traefik-auth/hashed_password-$WORKSPACE_NAME"
EOF

echo "[TRAEFIK-AUTH] ✓ Auth configuration created"
EOT
    : ""
  )
}

# =============================================================================
# Preview Buttons
# =============================================================================

# 1. Internal Preview (Coder Proxy) - Uses localhost, proxied through Coder
resource "coder_app" "preview_internal" {
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

# 2. Traefik Preview - External subdomain access
resource "coder_app" "preview_traefik" {
  count        = var.preview_mode == "traefik" ? var.workspace_start_count : 0
  agent_id     = var.agent_id
  slug         = "preview"
  display_name = "External Preview"
  icon         = "/icon/desktop.svg"
  url          = local.workspace_url
  external     = true
}

# =============================================================================
# Outputs
# =============================================================================

output "traefik_labels" {
  description = "Map of Traefik Docker labels to apply to workspace container"
  value       = local.traefik_labels
}

output "workspace_url" {
  description = "External workspace URL (HTTPS subdomain)"
  value       = local.workspace_url
}

output "preview_url" {
  description = "The active preview URL based on selected mode"
  value       = var.preview_mode == "traefik" ? local.workspace_url : "http://localhost:${var.exposed_port}"
}

output "auth_setup_script" {
  description = "Script to set up Traefik authentication (empty if public)"
  value       = local.traefik_auth_setup_script
}

output "auth_enabled" {
  description = "Whether authentication is enabled"
  value       = local.traefik_auth_enabled
}
