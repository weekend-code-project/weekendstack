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
  default     = false
}

variable "workspace_password" {
  description = "Password for basic auth (required when external preview is enabled)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "traefik_auth_dir" {
  description = "Host directory for Traefik auth files"
  type        = string
  default     = "/opt/stacks/traefik/auth"
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
  
  # Password file path inside Traefik container
  password_file = "/traefik-auth/htpasswd-${local.router_name}"
  
  # ==========================================================================
  # Traefik Labels (only when external preview is enabled)
  # ==========================================================================
  traefik_labels = var.external_preview_enabled ? merge(
    # Base routing labels
    {
      "traefik.enable"         = "true"
      "traefik.docker.network" = "coder-network"
      
      # HTTPS Router (external access via tunnel)
      "traefik.http.routers.${local.router_name}.rule"        = "Host(`${lower(var.workspace_name)}.${var.base_domain}`)"
      "traefik.http.routers.${local.router_name}.entrypoints" = "websecure"
      "traefik.http.routers.${local.router_name}.tls"         = "true"
      
      # Service configuration
      "traefik.http.services.${local.router_name}.loadbalancer.server.port" = var.preview_port
    },
    # Auth middleware labels (when password is set)
    var.workspace_password != "" ? {
      "traefik.http.routers.${local.router_name}.middlewares"                      = local.auth_middleware
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.usersfile"      = local.password_file
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.realm"          = "${var.workspace_owner}-workspace"
    } : {}
  ) : {}
}

# =============================================================================
# Auth Setup Script
# =============================================================================
# Generates htpasswd file for basic auth when external preview is enabled

resource "coder_script" "traefik_auth" {
  count = var.external_preview_enabled && var.workspace_password != "" ? 1 : 0
  
  agent_id           = var.agent_id
  display_name       = "Traefik Auth Setup"
  icon               = "/icon/lock.svg"
  run_on_start       = true
  start_blocks_login = false
  
  script = <<-SCRIPT
    #!/bin/bash
    
    WORKSPACE_NAME="${var.workspace_name}"
    USERNAME="${var.workspace_owner}"
    PASSWORD="${var.workspace_password}"
    AUTH_DIR="/traefik-auth"
    PASSWORD_FILE="$AUTH_DIR/htpasswd-${lower(var.workspace_name)}"
    
    echo "============================================================"
    echo "[TRAEFIK-AUTH] Setting up external preview authentication"
    echo "============================================================"
    
    # Check if auth directory is mounted
    if [ ! -d "$AUTH_DIR" ]; then
      echo "[TRAEFIK-AUTH] ERROR: $AUTH_DIR not mounted"
      exit 1
    fi
    echo "[TRAEFIK-AUTH] Auth directory found: $AUTH_DIR"
    
    # Install htpasswd if not available
    if ! command -v htpasswd >/dev/null 2>&1; then
      echo "[TRAEFIK-AUTH] Installing apache2-utils..."
      sudo apt-get update -qq >/dev/null 2>&1
      sudo apt-get install -y -qq apache2-utils >/dev/null 2>&1
    fi
    echo "[TRAEFIK-AUTH] htpasswd available"
    
    # Generate password hash
    echo "[TRAEFIK-AUTH] Generating password file..."
    htpasswd -nbB "$USERNAME" "$PASSWORD" | sudo tee "$PASSWORD_FILE" >/dev/null
    sudo chmod 644 "$PASSWORD_FILE"
    
    echo "[TRAEFIK-AUTH] Password file created: $PASSWORD_FILE"
    echo "[TRAEFIK-AUTH] External URL: ${local.workspace_url}"
    echo "[TRAEFIK-AUTH] Username: $USERNAME"
    echo "[TRAEFIK-AUTH] Setup complete"
    echo "============================================================"
  SCRIPT
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
