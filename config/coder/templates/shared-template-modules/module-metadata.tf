data "coder_parameter" "metadata_blocks" {
  name = "metadata_blocks" display_name = "Metadata Blocks" description = "Select metadata blocks to display." type = "list(string)" form_type = "multi-select" default = jsonencode(["cpu","ram","disk","ports"]) mutable = true order = 50
  option { name = "CPU Usage" value = "cpu" }
  option { name = "RAM Usage" value = "ram" }
  option { name = "Disk Usage" value = "disk" }
  option { name = "Ports" value = "ports" icon = "/icon/network.svg" }
  option { name = "SSH Port" value = "ssh_port" icon = "/icon/terminal.svg" }
  option { name = "Home Directory" value = "home_dir" }
  option { name = "Container Image" value = "image" }
}
module "metadata" { source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/metadata?ref=v0.1.0" enabled_blocks = data.coder_parameter.metadata_blocks.value != "" ? jsondecode(data.coder_parameter.metadata_blocks.value) : [] }
