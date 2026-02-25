# Base Template v2

A minimal Coder workspace template that provisions:
- Ubuntu container with Coder agent
- Persistent home directory via Docker volume
- Basic resource monitoring (CPU, Memory, Disk)
- Git identity from Coder workspace owner

## Usage

```bash
# Push to Coder
cd /opt/stacks/weekendstack/config/coder/v2
./scripts/push-template.sh base
```

## What's Included

| Feature | Status | Notes |
|---------|--------|-------|
| Container | ✅ | Ubuntu (codercom/enterprise-base) |
| Coder Agent | ✅ | With basic metadata |
| Home Persistence | ✅ | Docker named volume |
| Git Identity | ✅ | From workspace owner |

## What's NOT Included

This minimal template intentionally excludes features that require modules:

- ❌ SSH access - Add `ssh` module
- ❌ Git clone - Add `git` module  
- ❌ Traefik routing - Add `traefik` module
- ❌ Code-server IDE - Add `code-server` module
- ❌ Docker-in-Docker - Add `docker` module

## Extending This Template

Create a new template directory and add a `manifest.json`:

```json
{
  "name": "my-template",
  "extends": "base",
  "modules": [
    "feature/ssh",
    "feature/git",
    "feature/code-server"
  ]
}
```

## Testing

After pushing, create a test workspace:

1. Go to Coder UI → Templates → base
2. Click "Create Workspace"
3. Enter a name and click "Create"
4. Verify the workspace starts and shows CPU/Memory/Disk metrics
