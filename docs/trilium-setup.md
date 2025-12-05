# Trilium Notes Setup Guide

Trilium is a hierarchical note-taking application with focus on building personal knowledge bases.

## Quick Start

```bash
docker compose --profile productivity up -d trilium
```

## Access

- **Local:** http://192.168.2.50:8085
- **External:** https://trilium.weekendcodeproject.dev

## Environment Variables

```env
TRILIUM_PORT=8085
TRILIUM_DOMAIN=trilium.${BASE_DOMAIN}
TRILIUM_DATA_PATH=${DATA_PATH}/trilium
```

## First-Time Setup

On first launch, you'll be prompted to:
1. Set a secure password
2. Choose between creating a new document or restoring from backup

**Important:** Remember your password! There is no password recovery.

## Features

- Hierarchical tree structure for notes
- Rich text editor (WYSIWYG)
- Code notes with syntax highlighting
- Note versioning and history
- Full-text search
- Note cloning (same note in multiple places)
- Note attributes and labels
- Relation maps
- Day notes / journal
- Encrypted notes
- API for automation

## Note Types

- **Text:** Rich text with formatting
- **Code:** Syntax-highlighted code
- **Render HTML:** Rendered HTML content
- **Book:** Collection of notes displayed as book
- **Mermaid:** Diagrams using Mermaid syntax
- **Canvas:** Drawing canvas
- **Web View:** Embedded web page
- **Mind Map:** Visual mind mapping

## Data Storage

All data stored in: `${DATA_PATH}/trilium/`
- `document.db` - SQLite database with all notes
- `log/` - Application logs
- `backup/` - Automatic backups

## Backup Strategy

Trilium creates automatic backups. For additional backup:

```bash
cp -r ${DATA_PATH}/trilium/document.db /path/to/backup/
```

Or use the built-in backup feature in Settings → Sync.

## Keyboard Shortcuts

- `Ctrl+N` - New note
- `Ctrl+Shift+N` - New sub-note
- `Ctrl+F` - Search in note
- `Ctrl+Shift+F` - Global search
- `F5` - Reload
- `Alt+←/→` - Navigate history

## Cloning vs Moving

- **Moving:** Note exists in one place, hierarchy changes
- **Cloning:** Same note appears in multiple places, edits sync everywhere

## API Access

Enable API in Settings for automation. Example:
```bash
curl http://localhost:8085/api/notes/root \
  -H "Authorization: YOUR_TOKEN"
```

## Troubleshooting

### Database Locked

If you see database locked errors:
```bash
docker restart trilium
```

### Sync Issues

Clear sync state in Settings → Sync → Force full sync.
