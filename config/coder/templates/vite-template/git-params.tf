# =============================================================================
# Git Module (Vite Template Override - DISABLED)
# =============================================================================
# OVERRIDE NOTE: Git functionality disabled to isolate parameter flickering issue
# This prevents conditional git modules from being loaded during parameter preview

# Module: Git Identity (always loaded - sets up git config from workspace owner)
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity-module?ref=PLACEHOLDER"
  
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

# Git integration, GitHub CLI, and Gitea CLI modules are DISABLED in this override
# to prevent conditional module evaluation during parameter preview which causes flickering

# These module references are commented out to prevent "Module not loaded" warnings:
# - module.git_integration[0] 
# - module.github_cli[0]
# - module.gitea_cli[0]
