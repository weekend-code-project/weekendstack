# =============================================================================
# Traefik Routing Configuration
# =============================================================================

data "coder_parameter" "preview_mode" {
  name         = "preview_mode"
  display_name = "Preview Mode"
  description  = "How to access your workspace"
  type         = "string"
  default      = "traefik"
  mutable      = false
  order        = 90

  option {
    name  = "External URL (Traefik)"
    value = "traefik"
  }
  option {
    name  = "Internal Proxy (Coder)"
    value = "coder"
  }
}

data "coder_parameter" "workspace_secret" {
  name         = "workspace_secret"
  display_name = "Workspace Password (Optional)"
  description  = "Leave blank for public access, or set a password to require authentication"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 91
}

locals {
  enable_traefik         = data.coder_parameter.preview_mode.value == "traefik"
  workspace_secret_value = data.coder_parameter.workspace_secret.value != "" ? data.coder_parameter.workspace_secret.value : random_password.workspace_secret.result
  preview_mode          = data.coder_parameter.preview_mode.value
  
  # Traefik labels for routing
  traefik_labels = local.enable_traefik ? {
    "traefik.enable" = "true"
    "traefik.http.routers.${data.coder_workspace.me.name}.rule" = "Host(`${lower(data.coder_workspace.me.name)}.${var.base_domain}`)"
    "traefik.http.routers.${data.coder_workspace.me.name}.entrypoints" = "websecure"
    "traefik.http.routers.${data.coder_workspace.me.name}.tls" = "true"
    "traefik.http.services.${data.coder_workspace.me.name}.loadbalancer.server.port" = "80"
    "traefik.http.middlewares.${data.coder_workspace.me.name}-auth.basicauth.usersfile" = "/auth/${data.coder_workspace.me.name}.htpasswd"
    "traefik.http.routers.${data.coder_workspace.me.name}.middlewares" = data.coder_parameter.workspace_secret.value != "" ? "${data.coder_workspace.me.name}-auth" : ""
  } : {}
  
  # Auth setup script
  traefik_auth_script = data.coder_parameter.workspace_secret.value != "" ? join("\n", [
    "#!/bin/bash",
    "echo '[Traefik] 🔒 Setting up password protection...'",
    "sudo apt-get install -y apache2-utils > /dev/null 2>&1",
    "echo '${local.workspace_secret_value}' | sudo htpasswd -ci /traefik-auth/${data.coder_workspace.me.name}.htpasswd ${data.coder_workspace_owner.me.name}"
  ]) : "# No password protection"
}
