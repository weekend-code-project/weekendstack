# =============================================================================
# Git Parameters - WordPress Override
# =============================================================================
# WordPress template uses minimal git configuration without repository cloning

# Module: git-identity (basic git config)
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity-module?ref=PLACEHOLDER"
  
  git_author_name  = data.coder_workspace_owner.me.name
  git_author_email = data.coder_workspace_owner.me.email
}
