# Minimal traefik-routing module for testing

variable "workspace_name" {
  type = string
}

variable "workspace_owner" {
  type = string
}

variable "workspace_id" {
  type = string
}

variable "workspace_owner_id" {
  type = string
}

variable "make_public" {
  type = bool
}

variable "exposed_ports_list" {
  type = list(number)
}

output "traefik_labels" {
  value = {
    "traefik.enable" = "true"
  }
}

output "workspace_url" {
  value = "https://${var.workspace_name}.example.com"
}
