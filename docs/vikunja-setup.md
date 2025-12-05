# Vikunja Setup Guide

Vikunja is an open-source, self-hosted to-do list and task management application.

## Quick Start

```bash
docker compose --profile productivity up -d vikunja
```

## Access

- **Local:** http://192.168.2.50:3456
- **External:** https://vikunja.weekendcodeproject.dev

## Environment Variables

```env
VIKUNJA_PORT=3456
VIKUNJA_DOMAIN=vikunja.${BASE_DOMAIN}
VIKUNJA_DATA_PATH=${DATA_PATH}/vikunja

# Required settings
VIKUNJA_SERVICE_PUBLICURL=https://vikunja.${BASE_DOMAIN}
VIKUNJA_SERVICE_JWTSECRET=<generate-random-string>

# Optional
VIKUNJA_SERVICE_ENABLEREGISTRATION=true
VIKUNJA_CORS_ENABLE=false
```

## First-Time Setup

1. Navigate to the web interface
2. Click "Register" to create your account
3. Log in and create your first project

## Features

- Projects and sub-projects
- Tasks with due dates, priorities, labels
- Kanban boards
- Gantt charts
- Calendar view
- Task sharing and collaboration
- File attachments
- Reminders and notifications
- API for integrations

## Views

- **List View:** Traditional to-do list
- **Kanban:** Drag-and-drop boards
- **Gantt:** Timeline view for project planning
- **Table:** Spreadsheet-like view
- **Calendar:** Date-based view

## JWT Secret

Generate a secure JWT secret:
```bash
openssl rand -base64 32
```

## Data Storage

All data stored in: `${DATA_PATH}/vikunja/`
- `files/` - Uploaded attachments
- Database: SQLite by default

## Task Features

- **Due Dates:** With reminders
- **Priorities:** 1-5 urgency levels  
- **Labels:** Color-coded tags
- **Assignees:** Multi-user assignment
- **Comments:** Discussion on tasks
- **Attachments:** File uploads
- **Checklists:** Subtasks within tasks
- **Relations:** Link tasks together

## Keyboard Shortcuts

- `n` - New task
- `f` - Focus search
- `Escape` - Close modal/cancel

## CalDAV Integration

Vikunja supports CalDAV for calendar sync:
```
https://vikunja.weekendcodeproject.dev/dav/
```

## Troubleshooting

### Permission Errors

The container may need elevated permissions. The compose file uses `user: "0:0"` to run as root.

### CORS Issues

If you see CORS errors in browser console, verify:
- `VIKUNJA_SERVICE_PUBLICURL` matches your access URL
- `VIKUNJA_CORS_ENABLE=false` (Traefik handles CORS)

### API Issues

Reset authentication by clearing browser local storage for the Vikunja domain.
