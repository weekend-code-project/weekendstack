# =============================================================================
# Git Module
# =============================================================================
# DESCRIPTION:
#   Provides Git repository cloning and GitHub CLI installation.
#   Includes git identity configuration for all workspaces.
#
# PARAMETERS:
#   - clone_repo: Boolean toggle to enable repository cloning
#   - github_repo: Repository URL (conditional on clone_repo)
#   - install_github_cli: GitHub CLI installation toggle (conditional on clone_repo)
#
# DEPENDENCIES:
#   - template-modules/modules/git-identity: Git user configuration
#   - template-modules/modules/git-integration: Repository cloning
#   - template-modules/modules/github-cli: GitHub CLI installation
#
# OUTPUTS (via modules):
#   - git_identity.setup_script: Git config script
#   - git_integration.clone_script: Repository clone script
#   - github_cli.install_script: GitHub CLI installation script
#
# USAGE IN AGENT:
#   startup_script = join("\n", [
#     module.git_identity.setup_script,
#     try(module.git_integration[0].clone_script, ""),
#     (clone_enabled && cli_enabled) ? try(module.github_cli[0].install_script, "") : ""
#   ])
#
# NOTES:
#   - Git identity is always configured (unconditional)
#   - Repository cloning is conditional (count pattern)
#   - GitHub CLI is conditional on both clone_repo AND install_github_cli
# =============================================================================

# Parameter: Enable Git Clone
data "coder_parameter" "clone_repo" {
  name         = "clone_repo"
  display_name = "Clone Repository"
  description  = "Clone a Git repository into the workspace on first start."
  type         = "bool"
  form_type    = "switch"
  default      = "false"
  mutable      = false
  order        = 60
}

# Parameter: Repository URL (conditional on clone_repo)
data "coder_parameter" "github_repo" {
  count        = data.coder_parameter.clone_repo.value ? 1 : 0
  name         = "github_repo"
  display_name = "Repository URL"
  description  = "Git repository URL to clone (SSH or HTTPS)."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 61
  
  validation {
    regex = "^(https?://|git@).+$"
    error = "Repository URL must start with https://, http://, or git@"
  }
}

# Parameter: Install GitHub CLI (conditional on clone_repo)
data "coder_parameter" "install_github_cli" {
  count        = data.coder_parameter.clone_repo.value ? 1 : 0
  name         = "install_github_cli"
  display_name = "Install GitHub CLI"
  description  = "Install the GitHub CLI (gh) tool for GitHub operations."
  type         = "bool"
  form_type    = "switch"
  default      = "true"
  mutable      = false
  order        = 62
}

# Module: Git Identity (always loaded - sets up git config)
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity?ref=PLACEHOLDER"
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

# Module: Git Integration (conditional - only loaded when clone_repo is true)
module "git_integration" {
  count  = data.coder_parameter.clone_repo.value ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-integration?ref=PLACEHOLDER"
  
  github_repo_url = try(data.coder_parameter.github_repo[0].value, "")
}

# Module: GitHub CLI (conditional - only loaded when clone_repo AND install_github_cli are true)
module "github_cli" {
  count  = (data.coder_parameter.clone_repo.value && try(data.coder_parameter.install_github_cli[0].value, false)) ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/github-cli?ref=PLACEHOLDER"
}
