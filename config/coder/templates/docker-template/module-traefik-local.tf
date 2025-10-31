# =============================================================================
# MODULE: Traefik Routing & Authentication (Local Implementation)
# =============================================================================
# DESCRIPTION:
#   Provides Traefik routing labels and authentication setup for workspaces.
#   Local implementation avoids git module resolution issues in Coder UI.
#
# FEATURES:
#   - Dynamic Docker labels for Traefik routing
#   - Conditional authentication (public vs private workspaces)
#   - Automatic htpasswd file generation
#   - Traefik middleware configuration
#
# USAGE:
#   - Set make_public=true for public workspaces (no auth)
#   - Set make_public=false for private workspaces (requires password)
#   - Labels are automatically applied to docker_container in resources.tf
#   - Auth setup runs conditionally in startup script
#
# WHY LOCAL:
#   Git-based modules cause "Module not loaded" errors in Coder UI when
#   Terraform tries to resolve them before workspace creation. Local
#   implementation keeps all logic in the template itself.
# =============================================================================

# =============================================================================
# Parameters
# =============================================================================

# Toggle: Make workspace publicly accessible
data "coder_parameter" "make_public" {
  name         = "make_public"
  display_name = "Make Public"
  description  = "Make the workspace url publicly accessible without a password."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 10
}

# Password for private workspaces (only shown when make_public=false)
data "coder_parameter" "workspace_secret" {
  count        = data.coder_parameter.make_public.value ? 0 : 1
  name         = "workspace_secret"
  display_name = "Private Password"
  description  = "Enter a password to protect the workspace URL."
  type         = "string"
  default      = ""
  mutable      = true
  form_type    = "input"
  order        = 11
  
  validation {
    regex = "^.+$"
    error = "Suggested random password: ${random_password.workspace_secret.result}"
  }
}

# =============================================================================
# Traefik Routing Labels
# =============================================================================
# Generates Docker labels that Traefik uses to route traffic to this workspace.
# Labels include routing rules, service configuration, and optional authentication.

locals {
  # Domain configuration (customize for your environment)
  workspace_domain = "weekendcodeproject.dev"
  workspace_url    = "https://${lower(data.coder_workspace.me.name)}.${local.workspace_domain}"
  
  # Base Traefik labels (always applied to container)
  traefik_base_labels = {
    # Coder metadata
    "coder.owner"          = data.coder_workspace_owner.me.name
    "coder.owner_id"       = data.coder_workspace_owner.me.id
    "coder.workspace_id"   = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
    
    # Enable Traefik routing for this container
    "traefik.enable"         = "true"
    "traefik.docker.network" = "coder-network"
    
    # Router configuration (HTTPS with workspace subdomain)
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.rule"        = "Host(`${lower(data.coder_workspace.me.name)}.${local.workspace_domain}`)"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.entrypoints" = "websecure"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.tls"         = "true"
    
    # Service configuration (routes to first exposed port)
    "traefik.http.services.${lower(data.coder_workspace.me.name)}.loadbalancer.server.port" = element(local.exposed_ports_list, 0)
  }
  
  # Authentication labels (only added when workspace is private)
  traefik_auth_labels = {
    # Attach auth middleware to router
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.middlewares" = "${lower(data.coder_workspace.me.name)}-auth"
    
    # Reference htpasswd file created by auth setup script
    "traefik.http.middlewares.${lower(data.coder_workspace.me.name)}-auth.basicauth.usersfile" = "/traefik-auth/hashed_password-${data.coder_workspace.me.name}"
  }
  
  # Combine labels based on public/private setting
  # If make_public=false, merge auth labels into base labels
  traefik_labels = !data.coder_parameter.make_public.value ? merge(
    local.traefik_base_labels,
    local.traefik_auth_labels
  ) : local.traefik_base_labels
}

# =============================================================================
# Traefik Authentication Setup Script
# =============================================================================
# Bash script that runs during workspace startup to configure authentication.
# Creates htpasswd file and Traefik middleware config for private workspaces.
#
# REQUIREMENTS:
#   - /traefik-auth directory must be mounted from host
#   - apache2-utils package (provides htpasswd command)
#
# OUTPUT FILES:
#   - /traefik-auth/hashed_password-{workspace}: bcrypt password hash
#   - /traefik-auth/dynamic-{workspace}.yaml: Traefik middleware config
#
# BEHAVIOR:
#   - If make_public=true: Removes any existing auth files (cleanup)
#   - If make_public=false: Creates/updates auth files with new password
#   - Non-blocking: Gracefully skips if /traefik-auth not mounted

locals {
  traefik_auth_enabled = !data.coder_parameter.make_public.value
  
  traefik_auth_setup_script = <<-EOT
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
