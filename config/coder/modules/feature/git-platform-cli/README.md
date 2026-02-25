# git-platform-cli

Installs the appropriate Git platform CLI tool based on an explicit user selection.

## Why not auto-detect?

Self-hosted Gitea and GitLab are indistinguishable by URL pattern — both could be
`git@git.example.com:user/repo.git`. The user already knows their platform when
creating a workspace, so an explicit dropdown is cleaner and more reliable.

## Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `agent_id` | string | required | Coder agent ID |
| `git_cli` | string | `"none"` | Platform CLI to install: `none`, `github`, `gitlab`, `gitea` |
| `gitlab_host` | string | `""` | Self-hosted GitLab hostname (e.g. `git.example.com`). Set from `GITLAB_HOST` in `.env` at template push time — not a user-facing parameter. Empty = use gitlab.com |

## Outputs

| Output | Description |
|---|---|
| `platform` | The selected git_cli value |

## Behavior by platform

### `none`
No `coder_script` is created (`count = 0`). Nothing is installed.

### `github`
Installs `gh` via the official GitHub apt repository (keyring + source list + apt install).
Uses `flock` to serialize apt with other parallel startup scripts.
`gh auth login` is not run automatically — Coder's `$GIT_SSH_COMMAND` handles clone auth.

### `gitlab`
Installs `glab` via `packages.gitlab.com/gitlab-org/cli`.
If `gitlab_host` is non-empty, appends `export GITLAB_HOST=<host>` to `~/.bashrc` so
`glab` targets the self-hosted instance by default.

### `gitea`
Downloads the `tea` v0.9.2 binary from `dl.gitea.com` for the current architecture.
Supports `amd64`, `arm64`, and `armhf`. Works with any self-hosted Gitea — you specify
the host when running `tea login add`.

## Example usage

```hcl
module "git_platform_cli" {
  count  = data.coder_parameter.git_cli.value != "none" ? 1 : 0
  source = "./modules/feature/git-platform-cli"

  agent_id    = coder_agent.main.id
  git_cli     = data.coder_parameter.git_cli.value
  gitlab_host = data.coder_parameter.gitlab_host.value
}
```
