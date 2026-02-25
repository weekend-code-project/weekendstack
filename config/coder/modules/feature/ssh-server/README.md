# SSH Server + Key Generation Module

Provides SSH access to Coder workspaces with automatic key generation for Git operations.

## What It Does

1. **SSH Server** — Installs and starts OpenSSH server on a deterministic port
2. **User SSH Keys** — Generates an ed25519 key pair for the `coder` user (persists in home volume)
3. **Known Hosts** — Pre-configures known_hosts for GitHub, GitLab, Bitbucket, and Gitea
4. **Host Keys** — Persistent host keys in `~/.persist/ssh/` so SSH fingerprints don't change on restart
5. **Connection Info** — Displays SSH command and public key in workspace build log

## Inputs

| Variable | Type | Required | Description |
|---|---|---|---|
| `agent_id` | string | yes | Coder agent ID |
| `workspace_id` | string | yes | Workspace ID (for deterministic port) |
| `workspace_name` | string | no | Workspace name (default: "workspace") |
| `password` | string | yes | SSH password for the coder user |
| `host_ip` | string | no | Host IP for connection instructions (default: "127.0.0.1") |

## Outputs

| Output | Type | Description |
|---|---|---|
| `ssh_port` | number | External SSH port (23000-29999, deterministic) |
| `internal_port` | number | Internal sshd port (always 2222) |
| `connection_command` | string | Full SSH command for display |

## Usage in Template

```hcl
module "ssh_server" {
  source = "./modules/feature/ssh-server"

  agent_id       = coder_agent.main.id
  workspace_id   = data.coder_workspace.me.id
  workspace_name = local.workspace_name
  password       = local.ssh_password
  host_ip        = var.host_ip
}
```

The template must also publish the SSH port from the Docker container:

```hcl
resource "docker_container" "workspace" {
  # ...
  ports {
    internal = module.ssh_server.internal_port
    external = module.ssh_server.ssh_port
  }
}
```

## After Workspace Start

The build log will show:
- SSH connection command and password
- Your public key (copy this to GitHub/Gitea/GitLab)

From the workspace terminal, copy your public key:
```bash
cat ~/.ssh/id_ed25519.pub
```
