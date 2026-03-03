# Vite Template

Specialized Vite + Node.js workspace with framework scaffolding.

## Features

- **Vite project scaffolding** — auto-creates project if workspace is empty
- **Framework selection** (React, Vue, Svelte, Vanilla — with optional TypeScript)
- **Auto dev server** — starts `vite --host 0.0.0.0` on the preview port
- **Configurable Node.js version** via NVM
- **Package manager selection** (npm, pnpm, yarn)
- **Optional node_modules persistence**
- **Auto `npm install`** when package.json is present
- **Git integration** with repo cloning
- **Code-server** web IDE
- **SSH server** for remote access
- **External preview** via Traefik

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Node.js Version | LTS | Version to install |
| Vite Framework | React | Template for scaffolding |
| Package Manager | npm | npm, pnpm, or yarn |
| Persist node_modules | false | Separate volume |
| Preview Port | 8080 | Vite dev server port |
| External Preview | true | Enable Traefik routing |
| Workspace Password | *(empty)* | SSH + preview auth |
| Enable SSH | true | Start SSH server |
| Repository URL | *(empty)* | Git repo (skips scaffolding) |
| Git Platform CLI | None | gh, glab, or tea |

## Usage

```bash
./config/coder/scripts/push-template.sh vite
```
