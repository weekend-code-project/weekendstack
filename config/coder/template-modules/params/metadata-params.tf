# =============================================================================
# Metadata Module
# =============================================================================
# DESCRIPTION:
#   Provides workspace resource monitoring metadata blocks.
#   Displays CPU, RAM, disk usage, and other workspace information in Coder UI.
#
# PARAMETERS:
#   - metadata_blocks: Multi-select list of metadata to display
#
# DEPENDENCIES:
#   - template-modules/modules/metadata: Core metadata script generation
#
# OUTPUTS (via module.metadata):
#   - metadata_blocks: Array of metadata block configurations for agent
#
# USAGE IN AGENT:
#   metadata_blocks = module.metadata.metadata_blocks
#
# NOTES:
#   - Uses multi-select parameter (medium-high flickering risk)
#   - JSON encoded/decoded for list handling
#   - Mutable (can change after workspace creation)
# =============================================================================

# Parameter: Metadata Blocks to Display
data "coder_parameter" "metadata_blocks" {
  name         = "metadata_blocks"
  display_name = "Metadata Blocks"
  description  = "Select metadata blocks to display."
  type         = "list(string)"
  form_type    = "multi-select"
  default      = jsonencode(["cpu", "ram", "disk", "ports"])
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
    name  = "Ports"
    value = "ports"
    icon  = "/icon/network.svg"
  }

  option {
    name  = "SSH Port"
    value = "ssh_port"
    icon  = "/icon/terminal.svg"
  }

  option {
    name  = "Home Directory"
    value = "home_dir"
  }

  option {
    name  = "Container Image"
    value = "image"
  }
}

# Module: Metadata (always loaded, but content depends on selection)
module "metadata" {
  source         = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/metadata?ref=PLACEHOLDER"
  enabled_blocks = data.coder_parameter.metadata_blocks.value != "" ? jsondecode(data.coder_parameter.metadata_blocks.value) : []
}
