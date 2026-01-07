variable "base_domain" {
  type        = string
  description = "Base domain for workspace routing (e.g., example.com)"
  default     = "localhost"
}

variable "host_ip" {
  type        = string
  description = "Host IP address for port mappings"
  default     = "localhost"
}

variable "traefik_auth_dir" {
  type        = string
  description = "Directory path for Traefik authentication files"
  default     = "/tmp/traefik-auth"
}
