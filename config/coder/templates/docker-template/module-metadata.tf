# =============================================================================
# MODULE: Metadata
# =============================================================================
# Displays workspace information blocks (CPU, RAM, disk usage, etc.)
# =============================================================================

# Parameters
data "coder_parameter" "metadata_blocks" {
  name         = "metadata_blocks"
  display_name = "Metadata Blocks"
  description  = "Select which metadata blocks to display in the workspace dashboard."
  type         = "list(string)"
  form_type    = "multi-select"
  default      = jsonencode(["cpu", "ram", "disk"])
  mutable      = true
  order        = 50

  option {
    name  = "CPU Usage"
    value = jsonencode(["cpu"])
  }
  option {
    name  = "RAM Usage"
    value = jsonencode(["ram"])
  }
  option {
    name  = "Disk Usage"
    value = jsonencode(["disk"])
  }
  option {
    name  = "Home Directory"
    value = jsonencode(["home_dir"])
  }
  option {
    name  = "Container Image"
    value = jsonencode(["image"])
  }
}

# Module
module "metadata" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/metadata?ref=v0.1.0"
  
  enabled_blocks = data.coder_parameter.metadata_blocks.value != "" ? jsondecode(data.coder_parameter.metadata_blocks.value) : []
}
