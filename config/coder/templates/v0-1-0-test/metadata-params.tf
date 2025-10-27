# =============================================================================
# Metadata Parameters
# =============================================================================
# Required by git-modules/metadata module
# Copy this file to use metadata monitoring in your template

# Metadata Blocks Selection - Choose which metrics to display
data "coder_parameter" "metadata_blocks" {
  name         = "metadata_blocks"
  display_name = "Metadata Blocks"
  description  = "Select which resource metrics to display in the workspace dashboard"
  type         = "string"
  default      = "cpu,ram,disk,arch,ssh_port,validation"
  mutable      = true
  order        = 100

  option {
    name  = "All Metrics"
    value = "cpu,ram,disk,arch,ports,ssh_port,validation,load_avg,uptime"
  }
  option {
    name  = "Essential Only (CPU, RAM, Disk)"
    value = "cpu,ram,disk"
  }
  option {
    name  = "Development (CPU, RAM, Ports, Validation)"
    value = "cpu,ram,ports,validation"
  }
  option {
    name  = "SSH Workspace (CPU, RAM, SSH Port, Arch)"
    value = "cpu,ram,ssh_port,arch"
  }
  option {
    name  = "Minimal (CPU, RAM)"
    value = "cpu,ram"
  }
  option {
    name  = "Custom: Default"
    value = "cpu,ram,disk,arch,ssh_port,validation"
  }
  option {
    name  = "No Monitoring"
    value = ""
  }
}
