# Git Identity Module

Configures Git with user name and email for commits in the workspace.

## Usage

```hcl
module "git_identity" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/git-identity?ref=PLACEHOLDER"
  
  git_author_name  = data.coder_workspace_owner.me.full_name
  git_author_email = data.coder_workspace_owner.me.email
}

# Include in agent startup script
resource "coder_agent" "main" {
  startup_script = module.git_identity.setup_script
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| git_author_name | Git author name | string | yes |
| git_author_email | Git author email | string | yes |

## Outputs

| Name | Description |
|------|-------------|
| setup_script | Shell script to configure git identity |

## What It Does

1. Sets global git user.name
2. Sets global git user.email
3. Marks /home/coder/workspace as safe directory
