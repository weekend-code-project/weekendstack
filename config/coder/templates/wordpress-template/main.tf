terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# Workspace metadata
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# Docker provider configuration
provider "docker" {}

# Container image
data "docker_registry_image" "main" {
  name = "codercom/enterprise-base:ubuntu"
}

resource "docker_image" "main" {
  name          = data.docker_registry_image.main.name
  pull_triggers = [data.docker_registry_image.main.sha256_digest]
  keep_locally  = true
}

# Workspace secret for SSH password
resource "random_password" "workspace_secret" {
  length  = 16
  special = true
}

# MySQL database password
resource "random_password" "db_password" {
  length  = 32
  special = false
}

# Locals for base domain and paths
locals {
  actual_base_domain       = var.base_domain
  resolved_ssh_key_dir     = trimspace(var.ssh_key_dir) != "" ? var.ssh_key_dir : "/home/docker/.ssh"
  resolved_traefik_auth_dir = trimspace(var.traefik_auth_dir) != "" ? var.traefik_auth_dir : "/opt/stacks/weekendstack/config/traefik/auth"
}

# MySQL database container
resource "docker_container" "mysql" {
  count = data.coder_workspace.me.start_count
  image = "mysql:8.0"
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-mysql"
  
  env = [
    "MYSQL_ROOT_PASSWORD=${random_password.db_password.result}",
    "MYSQL_DATABASE=wordpress",
    "MYSQL_USER=wordpress",
    "MYSQL_PASSWORD=${random_password.db_password.result}"
  ]
  
  # Connect to coder-network
  networks_advanced {
    name = "coder-network"
    aliases = ["mysql-${data.coder_workspace.me.name}"]
  }
  
  # Persistent database storage
  volumes {
    container_path = "/var/lib/mysql"
    volume_name    = docker_volume.mysql_volume.name
  }
}

# MySQL data volume
resource "docker_volume" "mysql_volume" {
  name = "coder-${data.coder_workspace.me.id}-mysql"
  
  lifecycle {
    ignore_changes = all
  }
}

# Workspace container
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  
  hostname = data.coder_workspace.me.name
  
  # Required for Docker-in-Docker
  privileged = true
  
  # Connect to coder-network for Traefik routing
  networks_advanced {
    name = "coder-network"
  }
  
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(module.agent.agent_init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  # Docker host
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  env = [
    "CODER_AGENT_TOKEN=${module.agent.agent_token}",
    "DB_PASSWORD=${random_password.db_password.result}",
    "DB_HOST=mysql-${data.coder_workspace.me.name}",
    "PHP_VERSION=${data.coder_parameter.php_version.value}",
    "WP_URL=https://${lower(data.coder_workspace.me.name)}.${var.base_domain}"
  ]
  
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  
  # Mount SSH keys from host VM to workspace
  volumes {
    container_path = "/mnt/host-ssh"
    host_path      = local.resolved_ssh_key_dir
    read_only      = true
  }
  
  # Mount Traefik auth directory
  volumes {
    container_path = "/traefik-auth"
    host_path      = local.resolved_traefik_auth_dir
    read_only      = false
  }
  
  # Traefik labels
  dynamic "labels" {
    for_each = try(module.traefik[0].traefik_labels, {})
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# Home volume (persists user data)
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  
  lifecycle {
    ignore_changes = all
  }
}

# =============================================================================
# Modules
# =============================================================================

# Module: init-shell
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/init-shell-module?ref=PLACEHOLDER"
}

# Module: code-server
module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server-module?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  folder                = "/home/coder/workspace/wordpress"
}
