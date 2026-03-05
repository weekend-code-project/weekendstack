# Kottster Admin Panel Module

Provides [Kottster](https://kottster.app) as a database admin panel inside a Coder workspace.

## Supported Databases

| Database   | Knex Client | Notes |
|------------|-------------|-------|
| PostgreSQL | `pg`        | Sidecar container |
| MySQL      | `mysql`     | Sidecar container |
| MariaDB    | `mysql2`    | Sidecar container |
| SQLite     | `sqlite3`   | File-based, no sidecar |

## Inputs

| Name         | Type   | Required | Default     | Description |
|--------------|--------|----------|-------------|-------------|
| agent_id     | string | yes      | —           | Coder agent ID |
| db_type      | string | yes      | —           | One of: postgresql, mysql, mariadb, sqlite |
| db_host      | string | no       | "localhost" | Database host (ignored for sqlite) |
| db_port      | number | no       | 5432        | Database port (ignored for sqlite) |
| db_name      | string | yes      | —           | Database name or file path (sqlite) |
| db_user      | string | no       | ""          | Database username (ignored for sqlite) |
| db_password  | string | no       | ""          | Database password (ignored for sqlite) |
| admin_url    | string | yes      | —           | External URL for the admin panel |
| port         | number | no       | 5480        | Internal port for Kottster |

## Outputs

| Name        | Description |
|-------------|-------------|
| port        | Port Kottster is running on |
| url         | External URL for the admin panel |
| install_dir | Directory where Kottster is installed |

## Usage

```hcl
module "kottster_admin" {
  source = "./modules/feature/kottster-admin"

  agent_id    = coder_agent.main.id
  db_type     = "postgresql"
  db_host     = "postgres-myworkspace"
  db_port     = 5432
  db_name     = "devdb"
  db_user     = "postgres"
  db_password = random_password.db.result
  admin_url   = "https://myworkspace-admin.example.com"
}
```

## Notes

- Traefik labels must be added to the workspace container separately
- Kottster's identity provider (login) is always SQLite-based internally
- Data source configuration is auto-created on first start
- The module installs Node.js 20 if not present
