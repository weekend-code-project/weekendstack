# Git Integration Module

Provides Git repository cloning with user-configurable repository parameter.

## Usage

```hcl
module "git" {
  source = "git::https://github.com/weekend-code-project/weekendstack.git//config/coder/templates/git-modules/git-integration?ref=v0.1.0"
}

# Include in startup script (after git-identity and ssh-copy)
resource "coder_agent" "main" {
  startup_script = join("\n", [
    # ... init, git-identity, ssh-copy ...
    module.git.clone_script,
  ])
}
```

## Features

- User parameter for repository URL
- Smart cloning (mirror + working tree for speed)
- Automatic default branch detection
- Submodule initialization
- Idempotent (won't re-clone if .git exists)
