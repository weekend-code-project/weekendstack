data "coder_parameter" "make_public" {
  name         = "make_public"
  display_name = "Make Public"
  description  = "Make workspace URL publicly accessible."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 10
}

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

locals {
  # Base domain for public workspace URLs - read from TF_VAR_base_domain environment variable
  workspace_domain = var.base_domain
  # Construct a workspace-specific URL using the workspace name. The data sources
  # coder_workspace.me and coder_workspace_owner.me are provided by the Coder provider.
  workspace_url    = "https://${lower(data.coder_workspace.me.name)}.${local.workspace_domain}"

  traefik_base_labels = {
    "coder.owner"          = data.coder_workspace_owner.me.name
    "coder.owner_id"       = data.coder_workspace_owner.me.id
    "coder.workspace_id"   = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
    "traefik.enable"         = "true"
    "traefik.docker.network" = "coder-network"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.rule"        = "Host(`${lower(data.coder_workspace.me.name)}.${local.workspace_domain}`)"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.entrypoints" = "websecure"
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.tls"         = "true"
    "traefik.http.services.${lower(data.coder_workspace.me.name)}.loadbalancer.server.port" = element(local.exposed_ports_list, 0)
  }

  traefik_auth_labels = {
    "traefik.http.routers.${lower(data.coder_workspace.me.name)}.middlewares" = "${lower(data.coder_workspace.me.name)}-auth"
    "traefik.http.middlewares.${lower(data.coder_workspace.me.name)}-auth.basicauth.usersfile" = "/traefik-auth/hashed_password-${data.coder_workspace.me.name}"
  }

  # Normalize make_public value to a boolean
  make_public_value = try(data.coder_parameter.make_public.value, true)
  is_public         = tostring(local.make_public_value) == "true"

  # Decide final labels based on whether the workspace is public. If not public, merge auth labels.
  traefik_labels       = local.is_public ? local.traefik_base_labels : merge(local.traefik_base_labels, local.traefik_auth_labels)
  traefik_auth_enabled = local.is_public ? false : true
  traefik_auth_setup_script = <<-EOT
#!/bin/bash
set -e
WORKSPACE_NAME="${data.coder_workspace.me.name}"
USERNAME="${data.coder_workspace_owner.me.name}"
AUTH_ENABLED="${local.traefik_auth_enabled}"
if [ ! -d "/traefik-auth" ]; then echo "[TRAEFIK-AUTH] /traefik-auth not mounted; skipping"; exit 0; fi
if [ "$AUTH_ENABLED" = "true" ]; then
  if ! command -v htpasswd >/dev/null 2>&1; then sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y -qq apache2-utils >/dev/null 2>&1; fi
  sudo chown -R coder:coder /traefik-auth 2>/dev/null || true
  SECRET_VALUE="${try(data.coder_parameter.workspace_secret[0].value, "")}" 
  if [ -z "$SECRET_VALUE" ]; then echo "Password required"; exit 1; fi
  htpasswd -nbB "$USERNAME" "$SECRET_VALUE" | sudo tee "/traefik-auth/hashed_password-$WORKSPACE_NAME" >/dev/null
  sudo chmod 600 "/traefik-auth/hashed_password-$WORKSPACE_NAME"
  sudo tee "/traefik-auth/dynamic-$WORKSPACE_NAME.yaml" >/dev/null <<EOF
http:
  middlewares:
    $(echo "$WORKSPACE_NAME" | tr '[:upper:]' '[:lower:]')-auth:
      basicAuth:
        realm: "$USERNAME-$WORKSPACE_NAME-workspace"
        usersFile: "/traefik-auth/hashed_password-$WORKSPACE_NAME"
EOF
else
  sudo rm -f "/traefik-auth/hashed_password-$WORKSPACE_NAME" "/traefik-auth/dynamic-$WORKSPACE_NAME.yaml" 2>/dev/null || true
fi
EOT
}
