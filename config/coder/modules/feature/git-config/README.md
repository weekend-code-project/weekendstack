# Git Config + Repository Clone Module

Configures Git identity and optionally clones a repository into the workspace.

## Features

- Sets `git config --global user.name` and `user.email` from workspace owner
- Marks workspace folder as `safe.directory`
- Sets sensible defaults (`init.defaultBranch = main`, `pull.rebase = false`)
- Clones repository on first startup (if URL provided)
- Auto-pulls on subsequent startups (fast-forward only)
- SSH URL support with Gitea port 2222 auto-detection
- Mirror-clone approach (handles non-empty workspace directories)
- Tracks remote branches and initializes submodules
- Graceful SSH auth failure with public key display

## Dependencies

- **ssh-server module** — Generates SSH keys and configures known_hosts
- Agent `env` block — Sets `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, etc.

## Variables

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `agent_id` | string | yes | — | Coder agent ID |
| `owner_name` | string | yes | — | Git author name |
| `owner_email` | string | yes | — | Git author email |
| `workspace_folder` | string | no | `/home/coder/workspace` | Clone target |
| `repo_url` | string | no | `""` | Repository URL (SSH or HTTPS) |
| `gitea_host_pattern` | string | no | `gitea\|git\\.weekendcodeproject\\.dev` | Regex for Gitea host detection |

## Usage

```hcl
module "git_config" {
  source = "./modules/feature/git-config"

  agent_id         = coder_agent.main.id
  owner_name       = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  owner_email      = data.coder_workspace_owner.me.email
  workspace_folder = "/home/coder/workspace"
  repo_url         = data.coder_parameter.repo_url.value
}
```

## What This Module Does NOT Handle

- SSH key generation → handled by `ssh-server` module
- known_hosts setup → handled by `ssh-server` module
- Git env vars → set directly on `coder_agent.main.env`
- GitHub/Gitea CLI installation → separate modules
