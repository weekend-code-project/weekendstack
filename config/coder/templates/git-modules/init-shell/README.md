# Init Shell Module

Initializes the home directory structure for a new Coder workspace.

## Usage

```hcl
module "init_shell" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/init-shell?ref=v0.1.0"
}

# Include in agent startup script
resource "coder_agent" "main" {
  startup_script = module.init_shell.setup_script
}
```

## Inputs

None - this module has no variables.

## Outputs

| Name | Description |
|------|-------------|
| setup_script | Shell script to initialize home directory |

## What It Does

1. Creates ~/workspace directory
2. Creates ~/.config directory
3. Creates ~/.local/bin directory
4. Sets proper permissions

## Order

This should typically run **first** in the startup script sequence, before any other modules.
