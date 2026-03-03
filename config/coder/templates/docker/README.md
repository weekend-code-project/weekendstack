# Docker Template

A Docker-in-Docker workspace for container development.

## Features

- **Privileged container** with full Docker-in-Docker support
- **Code-server** web IDE
- **SSH server** for remote access
- **External preview** via Traefik reverse proxy
- **Docker data persistence** — pulled images survive restarts

## What's NOT Included

- Git integration (no repo cloning, no platform CLIs)
- Node.js or other language runtimes
- This is a blank canvas for Docker-based workflows

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Startup Command | `python3 -m http.server 8080` | Command to run at startup |
| Preview Port | `8080` | Port for the preview server |
| Auto-Generate HTML | `true` | Create default `index.html` |
| External Preview | `true` | Enable Traefik routing |
| Workspace Password | *(empty)* | Password for SSH + preview auth |
| Enable SSH | `true` | Start SSH server |

## Usage

```bash
./config/coder/scripts/push-template.sh docker
```
