# Minimal traefik-auth module for testingterraform {

  required_providers {

variable "workspace_name" {    coder = {

  type = string      source = "coder/coder"

}    }

    random = {

variable "workspace_owner" {      source = "hashicorp/random"

  type = string    }

}  }

}

variable "make_public" {

  type = bool# =============================================================================

}# Traefik Authentication Module

# =============================================================================

variable "workspace_secret" {# Configures Traefik basic authentication for workspace access.

  type      = string

  default   = ""variable "workspace_name" {

  sensitive = true  description = "Name of the workspace"

}  type        = string

}

output "traefik_auth_enabled" {

  value = !var.make_publicvariable "workspace_owner" {

}  description = "Owner username"

  type        = string

output "traefik_auth_setup_script" {}

  value = "echo 'traefik auth setup'"

}variable "make_public" {

  description = "Whether workspace is public (no auth)"
  type        = bool
}

variable "workspace_secret" {
  description = "Password for authentication (if not public)"
  type        = string
  default     = ""
  sensitive   = true
}

# Check if authentication should be enabled
locals {
  traefik_auth_enabled = !var.make_public
}

# Output for use in scripts
output "traefik_auth_enabled" {
  value = local.traefik_auth_enabled
}

# Bash script to configure Traefik authentication
output "traefik_auth_setup_script" {
  value = <<-EOT
    #!/bin/bash
    # Traefik Authentication Setup
    set -e
    
    WORKSPACE_NAME="${var.workspace_name}"
    USERNAME="${var.workspace_owner}"
    AUTH_ENABLED="${local.traefik_auth_enabled}"
    
    echo "[TRAEFIK-AUTH] Checking authentication status..."
    echo "[TRAEFIK-AUTH] Workspace: $WORKSPACE_NAME"
    echo "[TRAEFIK-AUTH] Auth enabled: $AUTH_ENABLED"
    
    # Check if /traefik-auth directory exists (it should be mounted from host)
    if [ ! -d "/traefik-auth" ]; then
      echo "[TRAEFIK-AUTH] ⚠ Warning: /traefik-auth directory not mounted"
      echo "[TRAEFIK-AUTH] Traefik authentication will not work without this mount"
      echo "[TRAEFIK-AUTH] Skipping auth setup..."
      echo ""
      exit 0  # Don't fail workspace creation, just skip auth
    fi
    
    if [ "$AUTH_ENABLED" = "true" ]; then
      echo "[TRAEFIK-AUTH] Setting up password protection..."
      
      # Install htpasswd if not present
      if ! command -v htpasswd >/dev/null 2>&1; then
        echo "[TRAEFIK-AUTH] Installing apache2-utils for htpasswd..."
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y -qq apache2-utils >/dev/null 2>&1
        echo "[TRAEFIK-AUTH] ✓ apache2-utils installed"
      else
        echo "[TRAEFIK-AUTH] ✓ htpasswd already available"
      fi
      
      # Ensure proper permissions on /traefik-auth
      sudo chown -R coder:coder /traefik-auth 2>/dev/null || true
      
      # Validate provided password and generate htpasswd file
      SECRET_VALUE="${var.workspace_secret}"
      if [ -z "$SECRET_VALUE" ]; then
        echo "[TRAEFIK-AUTH] ❌ Private Password is required when the workspace is not public."
        exit 1
      fi

      echo "[TRAEFIK-AUTH] Generating htpasswd file..."
      htpasswd -nbB "$USERNAME" "$SECRET_VALUE" \
        | sudo tee "/traefik-auth/hashed_password-$WORKSPACE_NAME" >/dev/null
      
      sudo chmod 600 "/traefik-auth/hashed_password-$WORKSPACE_NAME"
      
      # Generate Traefik middleware configuration
      echo "[TRAEFIK-AUTH] Creating Traefik middleware configuration..."
      sudo tee "/traefik-auth/dynamic-$WORKSPACE_NAME.yaml" >/dev/null <<EOF
http:
  middlewares:
    $(echo "$WORKSPACE_NAME" | tr '[:upper:]' '[:lower:]')-auth:
      basicAuth:
        realm: "$USERNAME-$WORKSPACE_NAME-workspace"
        usersFile: "/traefik-auth/hashed_password-$WORKSPACE_NAME"
EOF
      
      echo "[TRAEFIK-AUTH] ✓ Authentication configured"
      echo "[TRAEFIK-AUTH]   Username: $USERNAME"
      echo "[TRAEFIK-AUTH]   Password: [from workspace secret]"
      echo "[TRAEFIK-AUTH]   Middleware: $(echo "$WORKSPACE_NAME" | tr '[:upper:]' '[:lower:]')-auth"
      
    else
      echo "[TRAEFIK-AUTH] Authentication disabled (public workspace)"
      
      # Clean up auth files if they exist
      if [ -f "/traefik-auth/hashed_password-$WORKSPACE_NAME" ]; then
        echo "[TRAEFIK-AUTH] Removing old password file..."
        sudo rm -f "/traefik-auth/hashed_password-$WORKSPACE_NAME"
      fi
      
      if [ -f "/traefik-auth/dynamic-$WORKSPACE_NAME.yaml" ]; then
        echo "[TRAEFIK-AUTH] Removing old middleware config..."
        sudo rm -f "/traefik-auth/dynamic-$WORKSPACE_NAME.yaml"
      fi
      
      echo "[TRAEFIK-AUTH] ✓ Workspace is publicly accessible"
    fi
    
    echo ""
  EOT
}
