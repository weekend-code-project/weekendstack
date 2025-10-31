# =============================================================================
# Git Parameters
# =============================================================================

data "coder_parameter" "github_repo" {
  name         = "github_repo"
  display_name = "GitHub Repository"
  description  = "Git repository URL to clone (e.g., git@github.com:user/repo.git or https://github.com/user/repo.git). Leave empty to skip cloning."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 15
}
