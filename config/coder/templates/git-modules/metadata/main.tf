# =============================================================================
# MODULE: Metadata Blocks
# =============================================================================
# DESCRIPTION:
#   Provides configurable metadata blocks for workspace resource monitoring.
#   Templates can select which metrics to display in the Coder UI.
#
# ARCHITECTURE:
#   - Predefined metadata blocks for common metrics
#   - Selectable via block names
#   - Used by coder_agent metadata blocks
#
# OUTPUTS:
#   - metadata_blocks: List of selected metadata block definitions
#
# =============================================================================

# =============================================================================
# Variables
# =============================================================================

variable "enabled_blocks" {
  description = "List of metadata block names to enable (cpu, ram, disk, arch, ports, ssh_port, validation, load_avg, uptime)"
  type        = list(string)
  default     = ["cpu", "ram", "disk", "arch", "ports", "ssh_port", "validation"]
}

variable "custom_blocks" {
  description = "Custom metadata blocks to add"
  type = list(object({
    display_name = string
    script       = string
    interval     = number
    timeout      = number
  }))
  default = []
}

# =============================================================================
# Metadata Block Definitions
# =============================================================================

locals {
  # All available metadata blocks
  all_blocks = {
    cpu = {
      display_name = "CPU Usage"
      script       = "coder stat cpu"
      interval     = 10
      timeout      = 1
    }
    ram = {
      display_name = "RAM Usage"
      script       = "coder stat mem"
      interval     = 10
      timeout      = 1
    }
    disk = {
      display_name = "Disk Usage"
      script       = "coder stat disk --path $${HOME}"
      interval     = 60
      timeout      = 1
    }
    arch = {
      display_name = "Architecture"
      script       = "uname -m"
      interval     = 60
      timeout      = 5
    }
    ports = {
      display_name = "Ports"
      script       = "echo $PORTS"
      interval     = 60
      timeout      = 1
    }
    ssh_port = {
      display_name = "SSH Port"
      script       = "echo $${SSH_PORT}"
      interval     = 60
      timeout      = 1
    }
    validation = {
      display_name = "Validation"
      script       = "test -f /var/tmp/validation_summary.txt && cat /var/tmp/validation_summary.txt || echo 'PENDING'"
      interval     = 30
      timeout      = 1
    }
    load_avg = {
      display_name = "Load Average"
      script       = "uptime | awk -F'load average:' '{print $2}'"
      interval     = 30
      timeout      = 1
    }
    uptime = {
      display_name = "Uptime"
      script       = "uptime -p"
      interval     = 60
      timeout      = 1
    }
  }

  # Select only enabled blocks
  selected_blocks = [
    for name in var.enabled_blocks : local.all_blocks[name]
    if contains(keys(local.all_blocks), name)
  ]

  # Combine selected + custom blocks
  metadata_blocks = concat(local.selected_blocks, var.custom_blocks)
}

# =============================================================================
# Outputs
# =============================================================================

output "metadata_blocks" {
  description = "List of metadata block definitions"
  value       = local.metadata_blocks
}
