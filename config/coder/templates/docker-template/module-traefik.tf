# =============================================================================
# MODULE: Traefik (Authentication & Routing)
# =============================================================================
# Handles Traefik routing labels and authentication (COMMENTED OUT FOR TESTING)
# =============================================================================

# Parameters
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
}

# Modules
module "traefik_routing" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/routing-labels-test?ref=v0.1.0"
  
  workspace_name     = data.coder_workspace.me.name
  workspace_owner    = data.coder_workspace_owner.me.name
  workspace_id       = data.coder_workspace.me.id
  workspace_owner_id = data.coder_workspace_owner.me.id
  make_public        = data.coder_parameter.make_public.value
  exposed_ports_list = local.exposed_ports_list
}

module "traefik_auth" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/workspace-auth?ref=v0.1.0"
  
  workspace_name   = data.coder_workspace.me.name
  workspace_owner  = data.coder_workspace_owner.me.name
  make_public      = data.coder_parameter.make_public.value
  workspace_secret = try(data.coder_parameter.workspace_secret[0].value, "") != "" ? try(data.coder_parameter.workspace_secret[0].value, "") : random_password.workspace_secret.result
}
