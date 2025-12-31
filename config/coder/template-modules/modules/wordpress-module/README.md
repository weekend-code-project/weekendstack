# WordPress Template Module

This module installs and configures WordPress with PHP and Apache.

## Features

- PHP version selection (8.3, 8.2, 8.1, 8.0, 7.4)
- Apache web server with mod_rewrite
- MySQL database (in separate container)
- Automatic WordPress download and configuration
- Clean install screen on first access
- Persistent storage for WordPress files and database

## Variables

- `php_version` - PHP version to install
- `db_host` - MySQL container hostname
- `db_name` - MySQL database name
- `db_user` - MySQL database user
- `db_password` - MySQL database password
- `wp_url` - WordPress site URL (for Traefik routing)
- `workspace_name` - Workspace name (for container naming)

## Outputs

- `setup_script` - Complete WordPress setup script
- `metadata_blocks` - Status monitoring blocks
