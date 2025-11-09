# =============================================================================
# Preview Link - Shared Template Module
# =============================================================================
# This module wires up the preview-link git module with parameters from the
# template. It provides 3 preview modes: internal, traefik, and custom.

data "coder_parameter" "preview_link_mode" {
	name         = "preview_link_mode"
	display_name = "Preview Link Mode"
	description  = "Choose how the preview app URL is generated."
	type         = "string"
	default      = "traefik"
	mutable      = true
	order        = 23
	
	option {
		name  = "Internal (Coder Proxy)"
		value = "internal"
		icon  = "/icon/coder.svg"
	}
	option {
		name  = "Traefik (External Subdomain)"
		value = "traefik"
		icon  = "/icon/globe.svg"
	}
	option {
		name  = "Custom URL"
		value = "custom"
		icon  = "/icon/link.svg"
	}
}

data "coder_parameter" "traefik_base_domain" {
	count        = data.coder_parameter.preview_link_mode.value == "traefik" ? 1 : 0
	name         = "traefik_base_domain"
	display_name = "Base Domain"
	description  = "Base domain for Traefik URLs (workspace will be accessible at https://workspace-name.DOMAIN)"
	type         = "string"
	default      = var.base_domain
	mutable      = true
	form_type    = "input"
	order        = 24
}

data "coder_parameter" "custom_preview_url" {
	count        = data.coder_parameter.preview_link_mode.value == "custom" ? 1 : 0
	name         = "custom_preview_url"
	display_name = "Custom Preview URL"
	description  = "Enter your custom preview URL (e.g., https://myapp.example.com)"
	type         = "string"
	default      = ""
	mutable      = true
	form_type    = "input"
	order        = 25
	
	validation {
		regex = "^https?://.+"
		error = "URL must start with http:// or https://"
	}
}

# Call the preview-link git module
module "preview_link" {
	source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/preview-link?ref=v0.1.1"
	
	agent_id              = module.agent.agent_id
	workspace_name        = data.coder_workspace.me.name
	workspace_owner       = data.coder_workspace_owner.me.name
	base_domain           = try(data.coder_parameter.traefik_base_domain[0].value, local.actual_base_domain)
	exposed_port          = element(local.exposed_ports_list, 0)
	workspace_start_count = data.coder_workspace.me.start_count
	preview_mode          = data.coder_parameter.preview_link_mode.value
	custom_preview_url    = try(data.coder_parameter.custom_preview_url[0].value, "")
}
