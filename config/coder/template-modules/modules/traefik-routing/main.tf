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

variable "workspace_secret" {
  description = "Password for workspace auth - if empty, workspace is public (no auth)"
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
  # Auth is enabled when workspace_secret is not empty
  traefik_labels = var.preview_mode == "traefik" ? (
    var.workspace_secret != "" ? merge(local.traefik_base_labels, local.traefik_auth_labels) : local.traefik_base_labels
  ) : {}
  
  # Auth setup script (always runs, but checks password at runtime)
  traefik_auth_enabled = var.preview_mode == "traefik" && var.workspace_secret != ""
  
  # Always output the auth script - it will check if password is provided at runtime
  traefik_auth_setup_script = <<-EOT
#!/bin/bash
set -e

WORKSPACE_NAME="${var.workspace_name}"
USERNAME="${var.workspace_owner}"
SECRET_VALUE="${var.workspace_secret}"
PREVIEW_MODE="${var.preview_mode}"

echo "[TRAEFIK-DEBUG] Preview mode: $PREVIEW_MODE"
echo "[TRAEFIK-DEBUG] Password length: $${#SECRET_VALUE}"

# Only setup auth if password is provided AND using traefik mode
if [ "$PREVIEW_MODE" != "traefik" ]; then
  echo "[TRAEFIK-AUTH] Skipping auth setup (using internal preview mode)"
  exit 0
fi

if [ -z "$SECRET_VALUE" ]; then
  echo "[TRAEFIK-AUTH] No password provided - workspace is public"
  exit 0
fi

echo "[TRAEFIK-AUTH] Setting up password protection..."

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

# Generate htpasswd file
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

# Display auth info
echo "[TRAEFIK-AUTH] ✓ Password protection enabled"
echo "[TRAEFIK-AUTH] URL: https://${lower(var.workspace_name)}.${var.domain}"
echo "[TRAEFIK-AUTH] Username: $USERNAME"
echo ""  # Line break after module
EOT
}

# =============================================================================
# Preview Buttons
# =============================================================================

# 1. Internal Preview (Coder Proxy) - Uses localhost, proxied through Coder
resource "coder_app" "preview_internal" {
  count        = var.preview_mode == "internal" ? var.workspace_start_count : 0
  agent_id     = var.agent_id
  slug         = "preview"
  display_name = "Preview"
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
  display_name = "Preview"
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
