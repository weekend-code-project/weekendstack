# =============================================================================
# Git Module
# =============================================================================
# DESCRIPTION:
#   Provides Git repository cloning and auto-detected CLI installation.
#   Auto-detects whether to install GitHub CLI or Gitea CLI based on repo domain.
#   Includes git identity configuration for all workspaces.
#
# PARAMETERS:
#   - clone_repo: Boolean toggle to enable repository cloning
#   - github_repo: Repository URL (conditional on clone_repo)
#   - install_git_cli: Auto-detected CLI installation (conditional on clone_repo)
#
# DEPENDENCIES:
#   - template-modules/modules/git-identity: Git user configuration
#   - template-modules/modules/git-integration: Repository cloning
#   - template-modules/modules/github-cli: GitHub CLI installation
#   - template-modules/modules/gitea-cli: Gitea CLI installation
#
# OUTPUTS (via modules):
#   - git_identity.setup_script: Git config script
#   - git_integration.clone_script: Repository clone script
#   - github_cli.install_script: GitHub CLI installation script (auto-detected)
#   - gitea_cli.install_script: Gitea CLI installation script (auto-detected)
#
# USAGE IN AGENT:
#   startup_script = join("\n", [
#     module.git_identity.setup_script,
#     try(module.git_integration[0].clone_script, ""),
#     try(module.github_cli[0].install_script, ""),
#     try(module.gitea_cli[0].install_script, "")
#   ])
#
# NOTES:
#   - Git identity is always configured (unconditional)
#   - Repository cloning is conditional (count pattern)
#   - CLI auto-detection based on repo domain (github.com → gh, gitea → tea)
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

# Parameter: Install Git CLI (conditional on clone_repo)
data "coder_parameter" "install_git_cli" {
  count        = data.coder_parameter.clone_repo.value ? 1 : 0
  name         = "install_git_cli"
  display_name = "Install Git CLI"
  description  = "Auto-install GitHub CLI (gh) or Gitea CLI (tea) based on repository domain."
  type         = "bool"
  form_type    = "switch"
  default      = "true"
  mutable      = false
  order        = 62
}

# Auto-detect CLI based on repo domain
locals {
  repo_url = try(data.coder_parameter.github_repo[0].value, "")
  
  repo_domain = try(
    regex("https?://([^/]+)/", local.repo_url)[0],
    regex("git@([^:]+):", local.repo_url)[0],
    ""
  )
  
  is_github = contains([
    "github.com",
    "github.enterprise.com"
  ], local.repo_domain)
  
  is_gitea = contains([
    "gitea.com",
    "gitea.io",
    "git.weekendcodeproject.dev"
  ], local.repo_domain)
  
  # Default to GitHub CLI if domain not recognized
  install_cli   = try(data.coder_parameter.install_git_cli[0].value, false)
  use_github_cli = local.is_github || (!local.is_gitea && local.install_cli)
  use_gitea_cli  = local.is_gitea && local.install_cli
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

# Module: GitHub CLI (conditional - auto-detected for GitHub repos)
module "github_cli" {
  count  = (data.coder_parameter.clone_repo.value && local.use_github_cli) ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/github-cli?ref=PLACEHOLDER"
}

# Module: Gitea CLI (conditional - auto-detected for Gitea repos)
module "gitea_cli" {
  count  = (data.coder_parameter.clone_repo.value && local.use_gitea_cli) ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/gitea-cli?ref=PLACEHOLDER"
}
