# WordPress Template

A Coder template for WordPress development with customizable PHP versions.

## Features

- **PHP Version Selection**: Choose from PHP 8.3, 8.2, 8.1, 8.0, or 7.4
- **MySQL Database**: Dedicated MySQL 8.0 container with persistent storage
- **Apache Web Server**: Pre-configured with mod_rewrite and WordPress virtual host
- **Clean WordPress Install**: Fresh WordPress installation ready for setup
- **Traefik Routing**: Automatic HTTPS routing via Traefik
- **Git Integration**: Optional GitHub/Gitea repository cloning
- **SSH Access**: Optional SSH server with password authentication
- **Persistent Storage**: WordPress files and database persist across rebuilds

## Quick Start

1. Create a new workspace from the `wordpress-template`
2. Select your preferred PHP version
3. Configure optional features (Git repo, SSH, etc.)
4. Wait for workspace to start (~2-3 minutes for first-time setup)
5. Visit your workspace URL to complete WordPress installation

## WordPress Access

Your WordPress site will be available at:
```
https://[workspace-name].weekendcodeproject.dev
```

## Database Credentials

When setting up WordPress for the first time, use these credentials:

- **Database Name**: `wordpress`
- **Database User**: `wordpress`
- **Database Password**: Auto-generated (stored in workspace secret)
- **Database Host**: Auto-configured in wp-config.php

## File Structure

WordPress is installed at:
```
/home/coder/workspace/wordpress/
```

## Template Components

- **main.tf**: Infrastructure (workspace container, MySQL container, volumes)
- **agent-params.tf**: Coder agent configuration and startup script
- **wordpress-params.tf**: WordPress-specific parameters and module call
- **variables.tf**: Template variables (base_domain, host_ip, etc.)

## Modules Used

- `wordpress-module`: PHP, Apache, WordPress installation
- `coder-agent-module`: Coder agent orchestration
- `init-shell-module`: Basic shell setup
- `git-identity-module`: Git configuration
- `git-integration-module`: Repository cloning (optional)
- `github-cli-module` / `gitea-cli-module`: Git CLI tools (optional)
- `ssh-module`: SSH server (optional)
- `traefik-routing-module`: Reverse proxy routing
- `metadata-module`: Workspace metadata display

## Version

Template version: v1
