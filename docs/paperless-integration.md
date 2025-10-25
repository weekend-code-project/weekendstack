# Paperless-ngx Intake & Automation Guide

Paperless-ngx handles document ingestion directly from host folders. This guide explains how to feed documents into the stack, organize exports, and extend the workflow with automations—no Nextcloud required.

## 📂 Host Folder Layout

All directories are configurable in `.env`. Default values:

```
./volumes/paperless/
├── app/        # Application data and settings
├── postgres/   # PostgreSQL data directory
└── redis/      # Redis persistence

./files/paperless/
├── media/      # Processed documents (Paperless library)
├── consume/    # 📥 Drop documents here for ingestion
└── export/     # 📤 Paperless export target
```

- `${PAPERLESS_CONSUME_DIR}` → mounted at `/usr/src/paperless/consume`
- `${PAPERLESS_EXPORT_DIR}` → mounted at `/usr/src/paperless/export`
- `${PAPERLESS_MEDIA_DIR}` → holds all processed documents

Adjust these variables in `.env` if you prefer alternative paths.

## 🔄 Document Processing Workflow

1. **Capture**: Scan or save files directly into `${PAPERLESS_CONSUME_DIR}`.
2. **Process**: Paperless watches the consume folder (polling every 10 seconds), performs OCR, and indexes metadata.
3. **Organise**: Use the Paperless UI (`http://localhost:${PAPERLESS_PORT:-8082}`) to tag, classify, and search documents.
4. **Export (optional)**: Trigger exports in Paperless to populate `${PAPERLESS_EXPORT_DIR}` for downstream systems.

## 💡 Intake Tips

- **Subfolder tagging**: Creating folders under `consume/` automatically applies tag names matching those folders when the document is processed.
- **File naming**: Date prefixes like `2024-10-02_invoice.pdf` help Paperless detect document dates.
- **Supported formats**: PDFs, JPEG, PNG, TIFF, and Office documents (converted automatically).
- **Duplicates**: Duplicate detection is enabled by default; identical files are skipped.

## 🤖 Automation Ideas

### Scanner Drop Folder
- Configure your network scanner to upload directly to `${PAPERLESS_CONSUME_DIR}`.
- For remote devices, expose the folder via SMB/NFS or sync it using Syncthing/rclone.

### Email-to-Document Pipeline
- Use N8N to monitor an IMAP mailbox.
- Save attachments to `${PAPERLESS_CONSUME_DIR}` using an SFTP or local write node.

### Export Synchronization
- Watch `${PAPERLESS_EXPORT_DIR}` with N8N and push archives to cloud storage, S3, or Slack.
- Schedule cleanup jobs to prune exports after successful delivery.

## 🔧 Configuration Reference

Key environment variables (see `.env.example`):

- `PAPERLESS_CONSUME_DIR` – Host path for new documents.
- `PAPERLESS_EXPORT_DIR` – Host path for exports.
- `PAPERLESS_MEDIA_DIR` – Host path for processed documents.
- `PAPERLESS_SECRET_KEY` – Required application secret.
- `PAPERLESS_ADMIN_USER` / `PAPERLESS_ADMIN_PASSWORD` – Initial credentials.

## 🚀 Quick Start Checklist

1. Copy `.env.example` to `.env` and adjust Paperless paths if needed.
2. Launch the productivity profile:
   ```
   docker compose -f docker-compose.productivity.yml --profile productivity up -d
   ```
3. Open the UI at `http://localhost:${PAPERLESS_PORT:-8082}` and complete the onboarding wizard.
4. Drop a sample PDF into `${PAPERLESS_CONSUME_DIR}`.
5. Wait a few seconds, refresh the UI, and confirm the document is searchable.

Your paperless document workflow is now live! 📄✨
