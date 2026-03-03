# WordPress Template

A WordPress development workspace with MySQL and phpMyAdmin.

## Features

- **MySQL 8.0** sidecar container with persistent data volume
- **WordPress** auto-download and configuration
- **PHP version selection** (8.3, 8.2, 8.1)
- **Apache** web server with mod_rewrite
- **phpMyAdmin** for database management (separate Traefik subdomain)
- **Code-server** web IDE
- **SSH server** for remote access
- **External preview** via Traefik

## What's NOT Included

- Git integration
- Node.js or other language runtimes

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| PHP Version | 8.3 | PHP version for WordPress |
| External Preview | true | Enable Traefik routing |
| Workspace Password | *(empty)* | SSH + preview auth |
| Enable SSH | true | Start SSH server |

## Access Points

- **WordPress**: `https://{workspace}.{domain}`
- **phpMyAdmin**: `https://{workspace}-pma.{domain}`

## Usage

```bash
./config/coder/scripts/push-template.sh wordpress
```
