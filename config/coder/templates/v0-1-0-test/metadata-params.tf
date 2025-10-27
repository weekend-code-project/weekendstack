# =============================================================================
# Metadata Parameters
# =============================================================================
# Required by git-modules/metadata module
# Copy this file to use metadata monitoring in your template

locals {
  metadata_block_opts = [
    {
      name        = "CPU Usage"
      value       = jsonencode(["cpu"])
      description = "Show real-time CPU usage percentage"
    },
    {
      name        = "RAM Usage"
      value       = jsonencode(["ram"])
      description = "Show memory consumption and available RAM"
    },
    {
      name        = "Disk Usage"
      value       = jsonencode(["disk"])
      description = "Show disk space used and available in home directory"
    },
    {
      name        = "Architecture"
      value       = jsonencode(["arch"])
      description = "Display system architecture (e.g., x86_64, arm64)"
    },
    {
      name        = "Exposed Ports"
      value       = jsonencode(["ports"])
      description = "Show list of ports exposed by the workspace"
    },
    {
      name        = "SSH Port"
      value       = jsonencode(["ssh_port"])
      description = "Display the SSH port number for remote connections"
    },
    {
      name        = "Validation Status"
      value       = jsonencode(["validation"])
      description = "Show workspace validation checks and health status"
    },
    {
      name        = "Load Average"
      value       = jsonencode(["load_avg"])
      description = "Display system load average (1, 5, 15 minute intervals)"
    },
    {
      name        = "Uptime"
      value       = jsonencode(["uptime"])
      description = "Show how long the workspace has been running"
    }
  ]
}

# Metadata Blocks Multi-Select
data "coder_parameter" "metadata_blocks" {
  name         = "metadata_blocks"
  display_name = "Metadata Blocks"
  description  = "Select which resource metrics to display in the workspace dashboard"
  type         = "list(string)"
  form_type    = "multi-select"
  mutable      = true
  order        = 100

  dynamic "option" {
    for_each = local.metadata_block_opts
    content {
      name        = option.value.name
      value       = option.value.value
      description = option.value.description
    }
  }
}
