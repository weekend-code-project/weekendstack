# Focalboard Setup

Focalboard is a self-hosted project management tool, an alternative to Trello, Asana, and Notion.

## Configuration

Focalboard is configured in `docker-compose.productivity.yml` with the `productivity` profile.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FOCALBOARD_PORT` | 8097 | Local HTTP port |
| `FOCALBOARD_DOMAIN` | focalboard.${BASE_DOMAIN} | Public domain |
| `FOCALBOARD_MEMORY_LIMIT` | 512m | Memory limit |

## Starting Focalboard

```bash
docker compose --profile productivity up -d focalboard
```

## Access

| Type | URL |
|------|-----|
| Local | http://192.168.2.50:8097 |
| Public | https://focalboard.weekendcodeproject.dev |

## First-Time Setup

1. Open Focalboard in your browser
2. Click "Create an account" to register the first admin user
3. Create your first board (Kanban, Table, Gallery, or Calendar view)

## Features

- **Kanban Boards** - Drag and drop cards between columns
- **Table View** - Spreadsheet-like view of tasks
- **Calendar View** - See tasks on a calendar
- **Gallery View** - Visual card gallery
- **Templates** - Pre-built board templates
- **Customizable Properties** - Add custom fields to cards

## Data Storage

Focalboard uses a Docker volume (`focalboard-data`) for persistent storage, including:
- SQLite database
- Uploaded files

## Troubleshooting

### Check Logs

```bash
docker logs focalboard
```

### Container Won't Start

If you see "unable to open database file" errors, the data volume may have permission issues. The container runs as `nobody` user, so the volume must be writable.

Solution: Use a Docker volume (not bind mount) which Docker manages automatically.

### Health Check

```bash
docker ps --format '{{.Names}} {{.Status}}' | grep focalboard
curl -s http://192.168.2.50:8097/
```

## Backup

To backup Focalboard data:

```bash
docker run --rm -v weekendstack_focalboard-data:/data -v $(pwd):/backup alpine tar czf /backup/focalboard-backup.tar.gz /data
```

To restore:

```bash
docker run --rm -v weekendstack_focalboard-data:/data -v $(pwd):/backup alpine tar xzf /backup/focalboard-backup.tar.gz -C /
```
