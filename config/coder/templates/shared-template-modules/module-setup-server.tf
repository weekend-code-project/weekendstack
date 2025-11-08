# =============================================================================
# Setup Server - Shared Template Module (Parameters Only)
# =============================================================================
# This module only defines the parameters for server setup. Each template
# implements its own server setup logic in a local module-setup-server.tf file.
# The local module should define: local.setup_server_script

data "coder_parameter" "auto_generate_html" {
	name         = "auto_generate_html"
	display_name = "Serve Static Site"
	description  = "Toggle on to scaffold a static welcome page."
	type         = "bool"
	form_type    = "switch"
	default      = true
	mutable      = true
	order        = 20
}

data "coder_parameter" "exposed_ports" {
	name         = "exposed_ports"
	display_name = "Exposed Ports"
	description  = "Ports to expose (only used if Serve Static Site is disabled)."
	type         = "list(string)"
	form_type    = "tag-select"
	default      = jsonencode(["8080"])
	mutable      = true
	order        = 21
}

data "coder_parameter" "startup_command" {
	name         = "startup_command"
	display_name = "Startup Command"
	description  = "Command to run at startup (only used if Serve Static Site is disabled)."
	type         = "string"
	default      = ""
	mutable      = true
	order        = 22
}

locals {
	exposed_ports_raw  = try(data.coder_parameter.exposed_ports.value, jsonencode(["8080"]))
	exposed_ports_list = try(jsondecode(local.exposed_ports_raw), tolist(local.exposed_ports_raw), [tostring(local.exposed_ports_raw)])
}

# NOTE: Templates must implement their own local.setup_server_script
# See module-setup-server.tf in docker-template or node-template for examples


