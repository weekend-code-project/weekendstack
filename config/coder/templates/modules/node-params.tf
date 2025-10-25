# =============================================================================
# MODULE PARAMS: Node.js
# =============================================================================

data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node.js major version"
  description  = "Major version of Node.js to install (e.g., 18, 20)."
  type         = "string"
  default      = "20"
  mutable      = true
  order        = 40
}

data "coder_parameter" "node_modules_paths" {
  name         = "node_modules_paths"
  display_name = "node_modules directories"
  description  = "Comma-separated paths under the repo that should persist node_modules (e.g., .,apps/web,packages/ui)."
  type         = "string"
  default      = "."
  mutable      = true
  order        = 41
}
