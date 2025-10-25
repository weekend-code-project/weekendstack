# Variable for Coder access URL
variable "coder_access_url" {
  description = "URL for the Coder instance, used by the agent to connect. Should be http://coder:7080 inside the workspace container."
  type        = string
  default     = "http://coder:7080"
}

# Optional: absolute host path where workspace projects live.
# If provided (via TF_VAR_workspace_dir), we will bind-mount
#   <workspace_dir>/<workspace>
# to /home/coder/workspace inside the container so files are visible on the host.
# If empty, the workspace files will live inside the Docker volume only.
variable "workspace_dir" {
  description = "Absolute host path for workspace projects root (e.g., /mnt/workspace/wcp-coder/files/coder/workspace or .../workspaces)."
  type        = string
  default     = ""

  validation {
    condition     = var.workspace_dir == "" || can(regex("^/", var.workspace_dir))
    error_message = "workspace_dir must be an absolute host path (e.g., /mnt/workspace/wcp-coder/files/coder/workspace)."
  }
}

# Optional: host path for SSH keys directory (from TF_VAR_ssh_key_dir)
variable "ssh_key_dir" {
  description = "Absolute host path for SSH keys to copy into the workspace (optional)."
  type        = string
  default     = ""
}
# =============================================================================
# MODULE: Docker Resources
# =============================================================================
# DESCRIPTION:
#   Configures Docker volume and container resources for the workspace.
#   Creates persistent home volume and privileged container for Docker-in-Docker.
#   Includes Traefik routing labels for external access and authentication.
#
# DEPENDENCIES:
#   - data.coder_workspace.me
#   - data.coder_workspace_owner.me
#   - coder_agent.main
#   - local.traefik_labels (from traefik-routing.tf)
#
# OUTPUTS:
#   - docker_volume.home_volume: Persistent home directory volume
#   - docker_container.workspace: The workspace container
#
# ARCHITECTURE:
#   - Privileged container (required for Docker-in-Docker)
#   - Persistent /home/coder via Docker volume
#   - Host gateway access for local development
#   - Traefik integration via Docker labels
#   - Proper Coder labeling for resource tracking
#
# NOTES:
#   - Volume persists across workspace stops/starts
#   - Container is ephemeral (recreated on start)
#   - Uses codercom/enterprise-base:ubuntu as base image
#   - Traefik auth files mounted from host at /traefik-auth
#
# =============================================================================

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  
  lifecycle {
    ignore_changes = all
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
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  privileged = true  # Required for Docker-in-Docker
  
  # Ensure host-side workspace folder exists before bind-mounting
  depends_on = [
    null_resource.ensure_host_workspace_dir
  ]
  
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  
  # Connect directly via Docker network (no replace needed)
  # Use a positional parameter ($1) passed to sh -c so the URL is expanded at container runtime
  entrypoint = [
    "sh",
    "-c",
    "echo \"[DEBUG] CODER_ACCESS_URL is: $1\"; cat > /tmp/init_script.sh <<'INIT_SCRIPT'\n${coder_agent.main.init_script}\nINIT_SCRIPT\n# Replace any hardcoded localhost URL with the runtime CODER_ACCESS_URL (provided as $1)\nsed -i \"s|http://localhost:7080|$1|g\" /tmp/init_script.sh\n# Execute the fixed init script\nsh /tmp/init_script.sh",
    "unused",
    "${var.coder_access_url}"
  ]
  env        = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "CODER_ACCESS_URL=${var.coder_access_url}"
  ]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  # Connect to coder-network (matches original working template)
  networks_advanced {
    name = "coder-network"
  }
  
  # Persistent home directory
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Optional host bind mount for the project folder under /home/coder/workspace
  # This lets you see workspace files directly on the host filesystem.
  # Uses absolute path: ${var.workspace_dir}/${workspace}
  dynamic "mounts" {
    for_each = var.workspace_dir != "" ? [
      trimsuffix(var.workspace_dir, "/")
    ] : []
    content {
      target    = "/home/coder/workspace"
      source    = "${mounts.value}/${data.coder_workspace.me.name}"
      type      = "bind"
      read_only = false
    }
  }
  
  # Traefik authentication files (mounted from host) - fixed absolute path
  mounts {
    target = "/traefik-auth"
    source = "/mnt/workspace/wcp-coder/config/traefik/auth"
    type   = "bind"
  }

  # Optional: Host SSH keys directory (for ssh-copy module)
  dynamic "mounts" {
    for_each = var.ssh_key_dir != "" ? [
      trimsuffix(var.ssh_key_dir, "/")
    ] : []
    content {
      target = "/mnt/host-ssh"
      source = mounts.value
      type   = "bind"
    }
  }

  # Coder metadata labels
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
  
  # Traefik routing labels (includes auth if enabled)
  dynamic "labels" {
    for_each = local.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  # Optionally publish SSH port if SSH is enabled (internal fixed 2222)
  dynamic "ports" {
    for_each = data.coder_parameter.ssh_enable.value ? [1] : []
    content {
      internal = 2222
      external = tonumber(local.resolved_ssh_port)
      protocol = "tcp"
    }
  }
}

# Ensure host workspace directory exists when using bind mount
# We create /workspace/<workspace> inside the Coder control-plane container,
# where /workspace is a bind of the host ${WORKSPACE_DIR}. This guarantees the
# Docker bind source exists prior to container creation.
resource "null_resource" "ensure_host_workspace_dir" {
  # Re-run if workspace name or root dir changes
  triggers = {
    workspace_name = data.coder_workspace.me.name
    root_dir       = var.workspace_dir
  }

  provisioner "local-exec" {
    # Only run when workspace_dir is configured
    command = "sh -lc 'if [ -n \"${var.workspace_dir}\" ]; then mkdir -p /workspace/${data.coder_workspace.me.name}; fi'"
  }
}
