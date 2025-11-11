# =============================================================================
# Git Module
# =============================================================================
# DESCRIPTION:
#   Provides Git repository cloning with auto-detected CLI installation.
#   Auto-detects whether to install GitHub CLI or Gitea CLI based on repo domain.
#   If repository is provided, automatically clones and installs appropriate CLI.
#
# PARAMETERS:
#   - github_repo: Repository URL (empty = no clone, SSH recommended)
#
# DEPENDENCIES:
#   - template-modules/modules/git-identity: Git user configuration
#   - template-modules/modules/git-integration: Repository cloning
#   - template-modules/modules/github-cli: GitHub CLI installation
#   - template-modules/modules/gitea-cli: Gitea CLI installation
#
# OUTPUTS (via modules):
#   - git_identity.setup_script: Git config script (always runs)
#   - git_integration.clone_script: Repository clone script (if URL provided)
#   - github_cli.install_script: GitHub CLI installation (auto-detected)
#   - gitea_cli.install_script: Gitea CLI installation (auto-detected)
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
#   - If repo URL is empty, no clone or CLI installation occurs
#   - CLI auto-detection: github.com → gh, gitea → tea, other → none
#   - SSH URLs are recommended for private repositories
# =============================================================================

# Parameter: Repository URL (simple single field)
data "coder_parameter" "github_repo" {
  name         = "github_repo"
  display_name = "Repository URL"
  description  = "Git repository URL to clone (leave empty to skip). SSH recommended: git@github.com:user/repo.git"
  type         = "string"
  default      = ""
  mutable      = false
  order        = 60
  
  validation {
    regex = "^(https?://|git@|ssh://|).*$"
    error = "Repository URL must be empty or a valid git URL (https://, git@, or ssh://)"
  }
}

# Auto-detect CLI and clone based on repo URL
locals {
  repo_url    = data.coder_parameter.github_repo.value
  has_repo    = local.repo_url != ""
  
  # Extract domain from URL
  repo_domain = local.has_repo ? try(
    regex("https?://([^/]+)/", local.repo_url)[0],
    regex("git@([^:]+):", local.repo_url)[0],
    regex("ssh://git@([^/]+)/", local.repo_url)[0],
    ""
  ) : ""
  
  # Detect hosting service
  is_github = contains([
    "github.com",
    "github.enterprise.com"
  ], local.repo_domain)
  
  is_gitea = contains([
    "gitea.com",
    "gitea.io",
    "git.weekendcodeproject.dev"
  ], local.repo_domain)
  
  # Determine which CLI to install (if any)
  use_github_cli = local.has_repo && local.is_github
  use_gitea_cli  = local.has_repo && local.is_gitea
}

# Module: Git Identity (always loaded - sets up git config)
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity?ref=PLACEHOLDER"
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

# Module: Git Integration (conditional - only loaded when repo URL is provided)
module "git_integration" {
  count  = local.has_repo ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-integration?ref=PLACEHOLDER"
  
  github_repo_url = local.repo_url
}

# Module: GitHub CLI (conditional - auto-detected for GitHub repos)
module "github_cli" {
  count  = local.use_github_cli ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/github-cli?ref=PLACEHOLDER"
}

# Module: Gitea CLI (conditional - auto-detected for Gitea repos)
module "gitea_cli" {
  count  = local.use_gitea_cli ? 1 : 0
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/gitea-cli?ref=PLACEHOLDER"
}
