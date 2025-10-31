# =============================================================================
# MODULE: Init Shell
# =============================================================================
# Initializes home directory structure on first startup
# =============================================================================

module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/init-shell?ref=v0.1.0"
}
