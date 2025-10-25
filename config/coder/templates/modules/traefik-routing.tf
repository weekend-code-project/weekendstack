# =============================================================================
# MODULE: Traefik Routing
# =============================================================================
# DESCRIPTION:
#   Defines parameters and Docker labels for Traefik routing configuration.
#   Handles both public and authenticated workspace access via Traefik proxy.
#
# DEPENDENCIES:
#   - data.coder_workspace.me
#   - data.coder_workspace_owner.me
#   - data.coder_parameter.make_public (from workspace-secret.tf)
#
# PARAMETERS:
#   - exposed_ports: List of numeric ports to expose (add multiple)
#   - domain_name: Domain suffix for workspace URLs
#
# OUTPUTS:
#   - data.coder_parameter.exposed_ports
#   - data.coder_parameter.domain_name
#   - local.traefik_base_labels (map): Base Traefik labels for routing
#   - local.traefik_auth_labels (map): Authentication middleware labels
#   - local.traefik_labels (map): Combined labels based on auth status
#
# USAGE:
#   # In docker_container resource
#   dynamic "labels" {
#     for_each = local.traefik_labels
#     content {
#       label = labels.key
#       value = labels.value
#     }
#   }
#
# EXAMPLES:
#   # Public workspace (no auth)
#   make_public = true
#   exposed_ports = "8080"
#   domain_name = "example.com"
#   # Result: workspace accessible at https://workspace-name.example.com
#
#   # Protected workspace (with auth)
#   make_public = false
#   exposed_ports = "3000"
#   domain_name = "example.com"
#   # Result: https://workspace-name.example.com prompts for username/password
#
# NOTES:
#   - First port in exposed_ports is used as the default backend
#   - Workspace name is lowercased for URL compatibility
#   - Authentication labels are only added when make_public = false
#   - Traefik must be configured to watch Docker labels
#
# =============================================================================

# Hardcoded domain - change this to match your setup
locals {
  workspace_domain = "weekendcodeproject.dev"
}
locals {
  # Determine exposed ports even when the parameter is hidden (auto-generate HTML)
  exposed_ports_raw = try(
    data.coder_parameter.exposed_ports[0].value,
    jsonencode(["8080"])
  )

  # Robustly derive a list of ports regardless of how the provider returns the value
  # 1) Try to jsondecode if it's a JSON string representing a list (e.g., "[\"8080\"]")
  # 2) If it's already a list, keep as-is via tolist
  # 3) As a last resort, coerce scalar to a single-item list
  exposed_ports_list = try(
    jsondecode(local.exposed_ports_raw),
    tolist(local.exposed_ports_raw),
    [tostring(local.exposed_ports_raw)]
  )
}

# Validate that all ports are numeric and within range 1-65535
locals {
  invalid_ports = [
    for p in local.exposed_ports_list : p
    if !can(regex("^\\d+$", p)) || !can(tonumber(p)) || tonumber(p) < 1 || tonumber(p) > 65535
  ]
}

resource "null_resource" "validate_exposed_ports" {
  triggers = {
    ports = join(",", local.exposed_ports_list)
  }

  lifecycle {
    precondition {
      condition     = length(local.invalid_ports) == 0
      error_message = "Exposed Ports must be numeric between 1 and 65535. Invalid: ${join(",", local.invalid_ports)}"
    }
  }
}

# Base Traefik labels (always applied)
locals {
  traefik_base_labels = {
    "coder.owner"          = data.coder_workspace_owner.me.name
    "coder.owner_id"       = data.coder_workspace_owner.me.id
    "coder.workspace_id"   = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
    
    # Enable Traefik routing
    "traefik.enable" = "true"
    "traefik.docker.network" = "coder-network"
    
    # Router configuration
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.rule" = "Host(`${lower(data.coder_workspace.me.name)}.${local.workspace_domain}`)"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.entrypoints" = "websecure"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.tls" = "true"
    
    # Service configuration (use first port from exposed_ports)
    "traefik.http.services.${lower(data.coder_workspace.me.name)}.loadbalancer.server.port" = element(local.exposed_ports_list, 0)
  }
}

# Authentication labels (only when workspace secret is enabled)
locals {
  traefik_auth_labels = {
    # Attach auth middleware to router
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.middlewares" = "${lower(data.coder_workspace.me.name)}-auth"
    
    # Middleware references the htpasswd file created by traefik-auth.tf
    "traefik.http.middlewares.${lower(data.coder_workspace.me.name)}-auth.basicauth.usersfile" = "/traefik-auth/hashed_password-${data.coder_workspace.me.name}"
  }
}

# Combined labels - conditionally include auth labels
locals {
  # Include authentication labels when the workspace is NOT public
  traefik_labels = !try(data.coder_parameter.make_public.value, false) ? merge(
    local.traefik_base_labels,
    local.traefik_auth_labels
  ) : local.traefik_base_labels
}

# Helper: Workspace URL
locals {
  workspace_url = "https://${lower(data.coder_workspace.me.name)}.${local.workspace_domain}"
}
