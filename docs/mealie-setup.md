# Mealie Setup Guide

Mealie is a self-hosted recipe manager and meal planner.

## Quick Start

```bash
docker compose --profile personal up -d mealie
```

## Access

- **Local:** http://192.168.2.50:9925
- **External:** https://mealie.weekendcodeproject.dev

## Default Credentials

On first access, create an admin account through the web interface.

## Environment Variables

```env
MEALIE_PORT=9925
MEALIE_DOMAIN=mealie.${BASE_DOMAIN}
MEALIE_MEMORY_LIMIT=512m
```

## Features

- Recipe management with automatic import from URLs
- Meal planning calendar
- Shopping list generation
- Nutrition information
- Recipe scaling
- Mobile-friendly interface

## Data Storage

All data is stored in a Docker volume: `mealie-data`

## Importing Recipes

1. Click "Create Recipe" button
2. Paste a URL from a recipe website
3. Mealie will auto-extract recipe data
4. Edit and save

## Backup

Export your recipes via Settings → Backup → Create Backup
