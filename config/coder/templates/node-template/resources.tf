# =============================================================================
# Docker Resources
# =============================================================================

# Workspace Secret
resource "random_password" "workspace_secret" {
  length  = 16
  special = false
}

# Create workspace directory on host via Coder container's /workspace mount
resource "null_resource" "ensure_workspace_folder" {
  provisioner "local-exec" {
    command = "mkdir -p /workspace/${data.coder_workspace.me.name}"
  }
  
  triggers = {
    workspace_id = data.coder_workspace.me.id
  }
}

# Docker Container
resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "node:20-bullseye"
  privileged = true
  
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  
  # Ensure container is removed when workspace stops
  must_run              = true
  destroy_grace_seconds = 10
  
  entrypoint = [
    "sh",
    "-c",
    replace(module.agent.agent_init_script, "http://localhost:7080", "http://coder:7080"),
  ]
  
  env = [
    "CODER_AGENT_TOKEN=${module.agent.agent_token}",
    "CODER_ACCESS_URL=http://coder:7080",
      "PORT=${element(local.exposed_ports_list, 0)}",
      "PORTS=${join(",", local.exposed_ports_list)}"
  ]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  networks_advanced {
    name = "coder-network"
  }
  
  # Bind mount workspace directory from host
  # Directory is created via null_resource using Coder's /workspace mount
  mounts {
    target = "/home/coder/workspace"
    source = local.workspace_home_dir
    type   = "bind"
  }

  # Mount SSH keys from host (read-only)
  # Default: ./files/ssh (project directory)
  # Override in .env: SSH_KEY_DIR=/path/to/.ssh
  mounts {
    target    = "/mnt/host-ssh"
    source    = var.ssh_key_dir
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/traefik-auth"
    source = var.traefik_auth_dir
    type   = "bind"
  }

  # Traefik labels for routing
  dynamic "labels" {
    for_each = local.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }

  dynamic "ports" {
    for_each = module.ssh.ssh_enabled ? [1] : []
    content {
      internal = 2222
      external = tonumber(module.ssh.ssh_port)
      protocol = "tcp"
    }
  }
    dynamic "ports" {
      for_each = local.exposed_ports_list
      content {
        internal = tonumber(ports.value)
        external = tonumber(ports.value)
        protocol = "tcp"
      }
    }
  # Expose selected app ports (from shared-like parameters)
}
