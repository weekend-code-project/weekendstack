# =============================================================================
# MODULE: Git Identity & Integration
# =============================================================================
# Configures Git user identity and handles repository cloning
# =============================================================================

# Parameters
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

data "coder_parameter" "install_github_cli" {
  count        = data.coder_parameter.clone_repo.value ? 1 : 0
  name         = "install_github_cli"
  display_name = "Install GitHub CLI"
  description  = "Install the GitHub CLI (gh) tool in the workspace."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = false
  order        = 16
}

# Modules
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-identity?ref=v0.1.0"
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

module "git_integration" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-integration?ref=v0.1.0"
  
  github_repo_url = data.coder_parameter.clone_repo.value ? data.coder_parameter.github_repo[0].value : ""
}

module "github_cli" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/github-cli?ref=v0.1.0"
}
