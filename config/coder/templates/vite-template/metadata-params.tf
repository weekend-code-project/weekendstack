# =============================================================================
# Metadata Module (Vite Template Override - SIMPLIFIED)
# =============================================================================
# OVERRIDE NOTE: Simplified metadata to isolate parameter flickering
# Only includes basic built-in metadata options, no custom module metadata

# Parameter: Metadata Blocks to Display
data "coder_parameter" "metadata_blocks" {
  name         = "metadata_blocks"
  display_name = "Metadata Blocks"
  description  = "Select metadata blocks to display."
  type         = "list(string)"
  form_type    = "multi-select"
  default      = jsonencode(["cpu", "ram", "disk"])
  mutable      = true
  order        = 50

  option {
    name  = "CPU Usage"
    value = "cpu"
  }

  option {
    name  = "RAM Usage"
    value = "ram"
  }

  option {
    name  = "Disk Usage"
    value = "disk"
  }

  option {
    name  = "Architecture"
    value = "arch"
  }

  option {
    name  = "SSH Port"
    value = "ssh_port"
  }
}

# Module: Metadata (simplified - no custom blocks)
module "metadata" {
  source         = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata-module?ref=PLACEHOLDER"
  enabled_blocks = data.coder_parameter.metadata_blocks.value != "" ? jsondecode(data.coder_parameter.metadata_blocks.value) : []
  
  # NO custom_blocks to prevent circular dependencies
  custom_blocks = []
}
