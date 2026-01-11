# Code Server Module

Provides a web-based VS Code IDE using code-server.

## Usage

```hcl
module "code_server" {
  source = "./modules/feature/code-server"
  
  agent_id = coder_agent.main.id
  folder   = "/home/coder/workspace"
}
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `agent_id` | Coder agent ID (required) | - |
| `folder` | Folder to open in VS Code | `/home/coder/workspace` |
| `order` | Display order in UI | `1` |
| `settings` | VS Code settings map | See defaults below |
| `extensions` | List of extensions to install | `[]` |

### Default Settings

```json
{
  "workbench.colorTheme": "Default Dark+",
  "workbench.startupEditor": "none",
  "editor.fontSize": 16,
  "editor.tabSize": 2,
  "terminal.integrated.fontSize": 14
}
```

## Outputs

| Name | Description |
|------|-------------|
| `app_id` | Code server coder_app ID |

## Notes

- Uses the official Coder registry module: `registry.coder.com/modules/code-server/coder`
- VS Code Desktop button is disabled at the agent level, not in this module
