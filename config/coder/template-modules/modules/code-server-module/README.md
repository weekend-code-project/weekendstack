# VS Code Server Module

Configures VS Code Server (code-server) as the web-based IDE for Coder workspaces.

## Usage

```hcl
module "code_server" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/template-modules/modules/code-server?ref=PLACEHOLDER"
  
  agent_id              = module.agent.agent_id
  workspace_start_count = data.coder_workspace.me.start_count
  
  # Optional
  folder   = "/home/coder/workspace"
  order    = 1
  settings = {
    "editor.tabSize"               = 2
    "workbench.colorTheme"         = "Default Dark+"
    "editor.fontSize"              = 18
    "terminal.integrated.fontSize" = 18
    "workbench.startupEditor"      = "none"
  }
  extensions = [
    "github.copilot",
    "dbaeumer.vscode-eslint"
  ]
}
```

## Inputs

| Name | Description | Type | Required | Default |
|------|-------------|------|----------|---------|
| agent_id | Coder agent ID | string | yes | - |
| workspace_start_count | Start count | number | yes | - |
| folder | Folder to open | string | no | /home/coder/workspace |
| order | Display order | number | no | 1 |
| settings | VS Code settings | map(any) | no | See defaults |
| extensions | VS Code extensions | list(string) | no | [] |

## Outputs

| Name | Description |
|------|-------------|
| code_server_id | Code server app ID |

## Default Settings

```json
{
  "editor.tabSize": 2,
  "workbench.colorTheme": "Default Dark+",
  "editor.fontSize": 18,
  "terminal.integrated.fontSize": 18,
  "workbench.startupEditor": "none",
  "workbench.iconTheme": "let-icons"
}
```

## Features

1. **Registry Module**: Uses official Coder registry module
2. **Custom Settings**: Configurable editor preferences
3. **Extensions**: Install VS Code extensions automatically
4. **Folder Selection**: Opens to specific directory
5. **UI Integration**: Adds "VS Code" button in Coder dashboard

## Popular Extensions

```hcl
extensions = [
  "github.copilot",              # GitHub Copilot
  "dbaeumer.vscode-eslint",      # ESLint
  "esbenp.prettier-vscode",      # Prettier
  "ms-python.python",            # Python
  "golang.go",                   # Go
  "rust-lang.rust-analyzer",     # Rust
  "bradlc.vscode-tailwindcss",   # Tailwind CSS
]
```
