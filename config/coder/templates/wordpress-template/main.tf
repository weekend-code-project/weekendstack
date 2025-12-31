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

# MySQL database password
resource "random_password" "db_password" {
  length  = 32
  special = false
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
  
  # Traefik labels
  dynamic "labels" {
    for_each = module.traefik[0].labels
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
