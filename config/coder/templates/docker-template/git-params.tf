# =============================================================================
# Git Parameters
# =============================================================================

data "coder_parameter" "clone_repo" {
  name         = "clone_repo"
  display_name = "Clone Repository"
  description  = "Enable to clone a Git repository into the workspace on first startup."
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = false
  order        = 14
}

data "coder_parameter" "github_repo" {
  count        = data.coder_parameter.clone_repo.value ? 1 : 0
  name         = "github_repo"
  display_name = "Repository URL"
  description  = "Git repository URL to clone (e.g., git@github.com:user/repo.git or https://github.com/user/repo.git)."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 15
}
