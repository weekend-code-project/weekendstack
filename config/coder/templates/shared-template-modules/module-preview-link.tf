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

data "coder_parameter" "custom_preview_url" {
	count        = data.coder_parameter.preview_link_mode.value == "custom" ? 1 : 0
	name         = "custom_preview_url"
	display_name = "Custom Preview URL"
	description  = "Enter your custom preview URL (e.g., https://myapp.example.com)"
	type         = "string"
	default      = ""
	mutable      = true
	form_type    = "input"
	order        = 24
		validation {
			regex = "^https?://.+"
			error = "URL must start with http:// or https://"
		}
}

locals {
	preview_url = (
		data.coder_parameter.preview_link_mode.value == "traefik" ? local.workspace_url :
		data.coder_parameter.preview_link_mode.value == "custom" ? try(data.coder_parameter.custom_preview_url[0].value, "") :
		"http://localhost:${element(local.exposed_ports_list, 0)}"
	)
}
