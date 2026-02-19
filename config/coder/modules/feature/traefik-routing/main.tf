# =============================================================================
# Traefik Routing Module (v2)
# =============================================================================
# Provides external preview access via Traefik reverse proxy with:
#   - Docker labels for Traefik routing
#   - External preview button through tunnel
#   - Basic auth password protection (via usersFile - generated at runtime)
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

# Note: traefik_auth_dir is no longer needed as a variable.
# Both Traefik and workspace containers mount the host auth directory to /traefik-auth

# =============================================================================
# Locals
# =============================================================================

locals {
  # Fixed container mount point (same path Traefik uses)
  auth_mount_path = "/traefik-auth"
  
  # Workspace subdomain URL
  workspace_url = "https://${lower(var.workspace_name)}.${var.base_domain}"
  
  # Router name (lowercase, safe for Traefik)
  router_name = lower(var.workspace_name)
  
  # Auth middleware name
  auth_middleware = "${local.router_name}-auth"
  
  # Path to htpasswd file (inside Traefik's volume)
  htpasswd_file = "${local.auth_mount_path}/htpasswd-${local.router_name}"
  
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
    # Auth middleware labels (when password is set) - uses usersFile approach
    var.workspace_password != "" ? {
      "traefik.http.routers.${local.router_name}.middlewares"                 = local.auth_middleware
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.usersfile" = local.htpasswd_file
      "traefik.http.middlewares.${local.auth_middleware}.basicauth.realm"     = "${var.workspace_owner}-workspace"
    } : {}
  ) : {}
}

# =============================================================================
# Auth Setup Script (generates htpasswd file at runtime)
# =============================================================================

resource "coder_script" "setup_auth" {
  count = var.external_preview_enabled && var.workspace_password != "" ? 1 : 0
  
  agent_id     = var.agent_id
  display_name = "Setup Auth"
  icon         = "/icon/key.svg"
  run_on_start = true
  
  script = <<-EOT
    #!/bin/bash
    set -e
    
    echo "[AUTH] Setting up basic auth for external preview..."
    
    # Install htpasswd if not available
    if ! command -v htpasswd >/dev/null 2>&1; then
      echo "[AUTH] Installing apache2-utils for htpasswd..."
      sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils
    fi
    
    # Ensure auth directory exists and is writable
    # Uses fixed mount point /traefik-auth (same as Traefik sees)
    AUTH_DIR="${local.auth_mount_path}"
    if [ -d "$AUTH_DIR" ]; then
      echo "[AUTH] Auth directory exists: $AUTH_DIR"
    else
      echo "[AUTH] Creating auth directory: $AUTH_DIR"
      sudo mkdir -p "$AUTH_DIR"
    fi
    
    # Generate htpasswd file with bcrypt hash
    HTPASSWD_FILE="${local.htpasswd_file}"
    echo "[AUTH] Generating htpasswd file: $HTPASSWD_FILE"
    
    # Create the htpasswd entry (bcrypt hash)
    htpasswd -nbB "${var.workspace_owner}" "${var.workspace_password}" | sudo tee "$HTPASSWD_FILE" > /dev/null
    
    # Set permissions so Traefik can read it
    sudo chmod 644 "$HTPASSWD_FILE"
    
    echo "[AUTH] Basic auth configured for user: ${var.workspace_owner}"
    echo "[AUTH] Auth file: $HTPASSWD_FILE"
  EOT
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

output "htpasswd_file" {
  description = "Path to the htpasswd file for Traefik"
  value       = var.workspace_password != "" ? local.htpasswd_file : ""
}
