# Node Template

Full-featured Node.js development workspace.

## Features

- **Configurable Node.js version** via NVM (LTS, 22, 20, 18, latest)
- **Package manager selection** (npm, pnpm, yarn)
- **Optional node_modules persistence** — separate volume to keep workspace lean
- **Auto `npm install`** when package.json is present
- **Git integration** with repo cloning and platform CLI
- **Code-server** web IDE
- **SSH server** for remote access
- **External preview** via Traefik

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Node.js Version | LTS | Version to install |
| Package Manager | npm | npm, pnpm, or yarn |
| Persist node_modules | false | Store in separate volume |
| Startup Command | *(empty)* | Dev server command |
| Preview Port | 8080 | Port for dev server |
| External Preview | true | Enable Traefik routing |
| Workspace Password | *(empty)* | SSH + preview auth |
| Enable SSH | true | Start SSH server |
| Repository URL | *(empty)* | Git repo to clone |
| Git Platform CLI | None | gh, glab, or tea |

## Usage

```bash
./config/coder/scripts/push-template.sh node
```
