# Minimal traefik-auth module for testing# Minimal traefik-auth module for testing



variable "workspace_name" {variable "workspace_name" {

  type = string  type = string

}}



variable "workspace_owner" {variable "workspace_owner" {

  type = string  type = string

}}



variable "make_public" {variable "make_public" {

  type = bool  type = bool

}}



variable "workspace_secret" {variable "workspace_secret" {

  type      = string  type      = string

  default   = ""  default   = ""

  sensitive = true  sensitive = true

}}



locals {output "traefik_auth_enabled" {

  auth_enabled = var.make_public == false}

}

output "traefik_auth_setup_script" {

output "traefik_auth_enabled" {  value = "echo 'traefik auth setup'"

  value = local.auth_enabled}

}

output "traefik_auth_setup_script" {
  value = "echo 'traefik auth setup'"
}
