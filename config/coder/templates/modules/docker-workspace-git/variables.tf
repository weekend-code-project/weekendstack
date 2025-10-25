# =============================================================================
# MODULE VARIABLES: Docker Workspace
# =============================================================================

# Workspace identification
variable "workspace_name" {
  description = "Name of the workspace"
  type        = string
}

variable "workspace_owner" {
  description = "Username of the workspace owner"
  type        = string
}

variable "workspace_owner_id" {
  description = "UUID of the workspace owner"
  type        = string
}

variable "workspace_id" {
  description = "UUID of the workspace"
  type        = string
}

variable "workspace_state" {
  description = "Workspace state (start/stop)"
  type        = string
  default     = "start"
}

# Docker configuration
variable "docker_image" {
  description = "Docker image to use for the workspace"
  type        = string
  default     = "codercom/enterprise-base:ubuntu"
}

variable "container_cpu" {
  description = "CPU shares for the container (1024 = 1 CPU)"
  type        = number
  default     = 2048
}

variable "container_memory" {
  description = "Memory limit for the container in MB"
  type        = number
  default     = 4096
}

# Agent configuration
variable "agent_arch" {
  description = "Architecture of the Coder agent"
  type        = string
  default     = "amd64"
}

# Git configuration
variable "git_author_name" {
  description = "Git author name"
  type        = string
}

variable "git_author_email" {
  description = "Git author email"
  type        = string
}
