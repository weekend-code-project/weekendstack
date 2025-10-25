# Optional Nextcloud ↔ Paperless Integration Guide

> **Heads-up:** Nextcloud is no longer bundled with the default compose stack. Use this guide only if you operate a separate Nextcloud instance and want to integrate it with the Paperless-ngx directories managed in this repository.

## 🔗 Official Integration Options

Based on [Paperless-ngx GitHub Discussion #1789](https://github.com/paperless-ngx/paperless-ngx/discussions/1789), there are several proven integration methods available.

### ✅ **Option 1: Official Nextcloud Integration App (Recommended)**

**Available**: Nextcloud Hub 8+ (Nextcloud 29+)
- **App**: [`integration_paperless`](https://github.com/nextcloud/integration_paperless)
- **Install**: Available in Nextcloud App Store
- **Features**: Adds "Send to Paperless" file action menu in Nextcloud UI
- **Setup**: Configure at `/settings/user/connected-accounts`

**Benefits**:
- Native Nextcloud integration
- Direct file upload from Nextcloud to Paperless
- No file duplication (files moved, not copied)
- Official support and maintenance

### ✅ **Option 2: External Storage Mount (Host Folders)**

Mount Paperless folders as External Storage in Nextcloud:

```yaml
# Add to Nextcloud container volumes
nextcloud:
  volumes:
    # Paperless intake/export directories
  - ./files/paperless/consume:/var/www/html/data/paperless-intake
  - ./files/paperless/export:/var/www/html/data/paperless-export
  - ./files/paperless/media:/var/www/html/data/paperless-archive:ro
```

**Configuration in Nextcloud**:
1. Go to Admin → External Storage
2. Add Local storage pointing to:
   - `paperless-intake` (read/write) → Paperless consume folder
   - `paperless-archive` (read-only) → Processed documents

**Benefits**:
- Direct access to Paperless folders from Nextcloud UI
- No file duplication
- Users can see processing status
- Organized archive access

### ✅ **Option 3: FTP Bridge (Advanced)**

For better permission isolation:

```yaml
# Add FTP server for Paperless folders
paperless-ftp:
  image: stilliard/pure-ftpd
  container_name: paperless-ftp
  environment:
    PUBLICHOST: localhost
    FTP_USER_NAME: paperless
    FTP_USER_PASS: ${PAPERLESS_FTP_PASSWORD}
    FTP_USER_HOME: /home/paperless
  volumes:
  - ./files/paperless/consume:/home/paperless/intake
  - ./files/paperless/media:/home/paperless/archive:ro
  networks:
    - productivity-network
```

Then mount via FTP in Nextcloud External Storage.

## 🎯 **Multi-User Strategies**

### **User Identification Methods**

1. **ASN Barcodes/QR Codes**
   ```yaml
   environment:
     PAPERLESS_CONSUMER_ENABLE_ASN_BARCODE: true
     PAPERLESS_CONSUMER_ASN_BARCODE_PREFIX: "USER"
   ```

2. **Folder-based Tagging**
   ```yaml
   environment:
     PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS: true
   ```

3. **Filename Pattern Rules**
   - Use Paperless rules to auto-assign based on filename patterns
   - Example: `john_invoice_2024.pdf` → auto-assign to user "john"

### **Storage Path Templates**

Configure intelligent organization:
```
{created_year}/{correspondent}/{created_year}-{created_month}-{title}
/Users/{tag:user}/{created_year}/{correspondent}-{title}
/Shared/{document_type}/{created_year}/{title}
```

## 🔄 **Recommended Workflow**

1. **Install**: Official Nextcloud Paperless integration app
2. **Configure**: External Storage mounts for direct folder access
3. **Setup**: Document rules for automatic user/tag assignment
4. **Use**: 
   - Upload via Nextcloud → Auto-process in Paperless
   - View processed docs via External Storage mounts
   - Search/manage via Paperless web interface

## 📋 **Implementation Checklist**

- [ ] Install `integration_paperless` app in Nextcloud
- [ ] Configure External Storage for Paperless folders
- [ ] Set up document processing rules
- [ ] Test file upload workflow
- [ ] Configure storage path templates
- [ ] Set up user authentication sync (if needed)
- [ ] Test multi-user document separation

## 🔧 **Advanced Features Available**

- **Webhook Integration**: Post-consume scripts can trigger Nextcloud notifications
- **Metadata Sync**: Tags and correspondent info (custom development)
- **Search Integration**: OCR content searchable in Nextcloud (via Full Text Search app)
- **Group Permissions**: Map Paperless groups to Nextcloud groups

## 📚 **References**

- [Original GitHub Discussion](https://github.com/paperless-ngx/paperless-ngx/discussions/1789)
- [Official Integration App](https://apps.nextcloud.com/apps/integration_paperless)
- [Nextcloud External Storage Documentation](https://docs.nextcloud.com/server/latest/admin_manual/configuration_files/external_storage_configuration_gui.html)
- [Paperless Storage Path Templates](https://docs.paperless-ngx.com/advanced_usage/#file_name_handling)
