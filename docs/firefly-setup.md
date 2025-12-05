# Firefly III Setup Guide

Firefly III is a self-hosted personal finance manager.

## Quick Start

```bash
docker compose --profile personal up -d firefly
```

## Access

- **Local:** http://192.168.2.50:8086
- **External:** https://firefly.weekendcodeproject.dev

## Environment Variables

```env
FIREFLY_PORT=8086
FIREFLY_DOMAIN=firefly.${BASE_DOMAIN}

# Database Configuration
FIREFLY_MYSQL_ROOT_PASSWORD=<secure-password>
FIREFLY_MYSQL_DATABASE=firefly
FIREFLY_MYSQL_USER=firefly
FIREFLY_MYSQL_PASSWORD=<secure-password>

# App Configuration
FIREFLY_APP_KEY=<32-character-key>  # Required! Generate with: head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
FIREFLY_APP_URL=https://firefly.${BASE_DOMAIN}
```

## Generating App Key

The `FIREFLY_APP_KEY` must be exactly 32 characters:

```bash
head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
```

## First-Time Setup

1. Navigate to the web interface
2. Create your first user account
3. Set up your bank accounts
4. Configure your currency preferences

## Features

- Transaction management (income, expenses, transfers)
- Budget tracking
- Bill reminders
- Rule-based categorization
- Reporting and charts
- Import from banks (CSV, Spectre, bunq)
- Multi-currency support

## Data Model

- **Accounts:** Asset, expense, revenue, liability accounts
- **Transactions:** Withdrawals, deposits, transfers
- **Budgets:** Monthly spending limits by category
- **Categories:** Organize transactions
- **Tags:** Additional organization
- **Rules:** Auto-categorize transactions

## Data Storage

- Database: MariaDB container (`firefly-db`)
- Upload files: `firefly-upload` volume

## Backup

Back up the MariaDB database:
```bash
docker exec firefly-db mysqldump -u firefly -p firefly > firefly_backup.sql
```
