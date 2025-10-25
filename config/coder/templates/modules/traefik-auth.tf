# =============================================================================
# MODULE: Traefik Authentication
# =============================================================================
# DESCRIPTION:
#   Configures Traefik basic authentication for workspace access.
#   When enabled, generates an htpasswd file and Traefik middleware configuration
#   to protect workspace endpoints with username/password authentication.
#
# DEPENDENCIES:
#   - data.coder_workspace.me
#   - data.coder_workspace_owner.me
#   - data.coder_parameter.show_workspace_secret[0] (from workspace-secret.tf)
#   - random_password.workspace_secret (from workspace-secret.tf)
#
# PARAMETERS:
#   - show_workspace_secret (bool): Toggle for authentication (from workspace-secret.tf)
#
# CONFIGURATION:
#   This module uses the workspace secret as the authentication password.
#   The htpasswd file and Traefik middleware config are created in /traefik-auth
#   which should be mounted from the host.
#
# USAGE:
#   # In coder_agent startup_script
#   startup_script = join("\n", [
#     local.traefik_auth_setup,
#     # ... other modules
#   ])
#
#   # Required volume mount in docker_container
#   mounts {
#     target = "/traefik-auth"
#     source = "/absolute/path/to/traefik/auth"
#     type   = "bind"
#   }
#
# EXAMPLES:
#   # Enable authentication by toggling workspace secret
#   show_workspace_secret = true
#
#   # Disable authentication (public workspace)
#   show_workspace_secret = false
#
# OUTPUTS:
#   - local.traefik_auth_setup (string): Bash script to configure authentication
#   - local.traefik_auth_enabled (bool): Whether auth is enabled
#
# NOTES:
#   - Requires apache2-utils package for htpasswd command
#   - Password file location: /traefik-auth/hashed_password-<workspace>
#   - Middleware config: /traefik-auth/dynamic-<workspace>.yaml
#   - Traefik must have /traefik-auth mounted to read these files
#   - Files are cleaned up when authentication is disabled
#
# =============================================================================

# Check if authentication should be enabled (authentication is enabled when NOT public)
locals {
  traefik_auth_enabled = !try(data.coder_parameter.make_public.value, false)
}

# -----------------------------------------------------------------------------
# Workspace access parameters (moved from workspace-secret.tf)
# -----------------------------------------------------------------------------

# Toggle: Make Public (when true, workspace is public and secret is hidden)
data "coder_parameter" "make_public" {
  name         = "make_public"
  display_name = "Make Public"
  description  = "Make the workspace url publicly accessible without a password."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 1
}

# Generate a random password (stable across restarts)
resource "random_password" "workspace_secret" {
  length  = 24
  special = false

  lifecycle {
    create_before_destroy = true
  }

  keepers = {
    workspace_id = data.coder_workspace.me.id
  }
}

# Display the password as a workspace parameter (conditionally shown with count)
data "coder_parameter" "workspace_secret" {
  # Only show the secret when the workspace is private (make_public = false)
  count        = data.coder_parameter.make_public.value ? 0 : 1
  
  name         = "workspace_secret"
  display_name = "Private Password"
  description  = "Enter a password to protect the workspace URL."
  type         = "string"
  default      = ""
  mutable      = true
  form_type    = "input"
  order        = 2
  
  validation {
    regex = "^.+$"
    error = "Suggested random password: ${random_password.workspace_secret.result}"
  }
}

# Bash script to configure Traefik authentication
locals {
  traefik_auth_setup = <<-EOT
    #!/bin/bash
    # Traefik Authentication Setup
    set -e
    
    WORKSPACE_NAME="${data.coder_workspace.me.name}"
    USERNAME="${data.coder_workspace_owner.me.name}"
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
  SECRET_VALUE="${try(data.coder_parameter.workspace_secret[0].value, "")}"
      if [ -z "$SECRET_VALUE" ]; then
        echo "[TRAEFIK-AUTH] ❌ Private Password is required when the workspace is not public."
        echo "[TRAEFIK-AUTH] Hint: Enter your own password or use the random one suggested by the validation error."
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
