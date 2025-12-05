# Kavita Setup Guide

Kavita is a fast, feature-rich reading server for manga, comics, and eBooks.

## Access URLs

| Type | URL |
|------|-----|
| Local | http://192.168.2.50:5000 |
| Public | https://kavita.weekendcodeproject.dev |

## Starting Kavita

```bash
docker compose --profile media up -d kavita
```

## Initial Setup

1. Navigate to http://192.168.2.50:5000
2. Create an admin account (first user becomes admin)
3. Go to **Admin Dashboard** → **Libraries**
4. Click **Add Library** and configure:
   - **Name**: e.g., "Manga", "Comics", "Books"
   - **Type**: Select appropriate type (Manga, Comic, Book, Image)
   - **Folders**: Add `/manga` (maps to host path)
5. Save and let Kavita scan your library

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KAVITA_PORT` | 5000 | Host port for web UI |
| `KAVITA_DOMAIN` | kavita.${BASE_DOMAIN} | Domain for Traefik routing |
| `KAVITA_LIBRARY_PATH` | ./files/kavita/library | Host path for media files |
| `KAVITA_MEMORY_LIMIT` | 512m | Container memory limit |

## Adding Content

Place your content in the library folder on the host:

```bash
# Default location
./files/kavita/library/

# Example structure
./files/kavita/library/
├── Manga/
│   ├── Series Name/
│   │   ├── Volume 01.cbz
│   │   └── Volume 02.cbz
├── Comics/
│   └── Comic Series/
│       └── Issue 001.cbr
└── Books/
    └── Author Name/
        └── Book Title.epub
```

### Supported Formats

- **Manga/Comics**: `.cbz`, `.cbr`, `.cb7`, `.cbt`, `.zip`, `.rar`, `.7z`, `.tar`
- **eBooks**: `.epub`, `.pdf`
- **Images**: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`

## Library Types

| Type | Best For |
|------|----------|
| Manga | Japanese manga with right-to-left reading |
| Comic | Western comics with left-to-right reading |
| Book | eBooks (epub, pdf) |
| Image | Image collections, art books |

## Features

- **OPDS Support**: Connect e-readers via OPDS catalog
- **Reading Progress**: Syncs across devices
- **Collections**: Organize content into custom collections
- **Smart Filters**: Filter by genre, tags, reading status
- **User Management**: Multiple users with separate progress
- **Metadata**: Automatic metadata fetching

## OPDS Feed

Connect your e-reader or reading app using:
```
http://192.168.2.50:5000/api/opds/{api-key}
```

Get your API key from **User Settings** → **3rd Party Clients**.

## Mobile Apps

Kavita works with OPDS-compatible readers:
- **iOS**: Panels, Chunky Reader
- **Android**: Librera, Moon+ Reader

## Troubleshooting

### Library not scanning
```bash
docker logs kavita --tail 50
```

### Check container status
```bash
docker ps --filter name=kavita
```

### Restart Kavita
```bash
docker compose --profile media restart kavita
```
