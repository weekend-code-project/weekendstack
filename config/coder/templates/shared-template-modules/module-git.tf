data "coder_parameter" "clone_repo" {
	name         = "clone_repo"
	display_name = "Clone Repository"
	description  = "Clone a Git repository into workspace."
	type         = "bool"
	default      = false
	mutable      = false
	order        = 14
}

data "coder_parameter" "github_repo" {
	name         = "github_repo"
	display_name = "Repository URL"
	description  = "Git repository URL to clone."
	type         = "string"
	default      = ""
	mutable      = false
	order        = 15
}

data "coder_parameter" "install_github_cli" {
	name         = "install_github_cli"
	display_name = "Install GitHub CLI"
	description  = "Install GitHub CLI tool."
	type         = "bool"
	default      = true
	mutable      = false
	order        = 16
}

module "git_identity" {
	source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-identity?ref=v0.1.0"
  
	git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
	git_author_email = data.coder_workspace_owner.me.email
}

module "git_integration" {
	source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-integration?ref=v0.1.0"
  
	# FIX: Always pass the URL, let the git module handle empty string
	github_repo_url = data.coder_parameter.github_repo.value
}

module "github_cli" {
	source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/github-cli?ref=v0.1.0"
}
