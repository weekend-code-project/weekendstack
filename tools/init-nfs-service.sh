#!/usr/bin/env bash
#
# Initialize NFS volume folder structure for WeekendStack services
#
# Usage: ./tools/init-nfs-service.sh <service> [folder1] [folder2] ...
#
# Examples:
#   ./tools/init-nfs-service.sh immich upload library profile thumbs encoded-video backups
#   ./tools/init-nfs-service.sh paperless media consume export
#   ./tools/init-nfs-service.sh navidrome music
#   ./tools/init-nfs-service.sh ollama models
#
# Requirements:
#   - Docker compose project must be started
#   - NFS volume must be defined in docker-compose file
#   - NFS_SERVER_IP must be configured in .env
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Validate arguments
if [ $# -lt 1 ]; then
    error "Usage: $0 <service> [folder1] [folder2] ...
    
Available services:
  immich        - Photo/video management (folders: upload library profile thumbs encoded-video backups)
  paperless     - Document management (folders: media consume export)
  navidrome     - Music streaming (folders: music)
  kavita        - eBook/manga reader (folders: library)
  ollama        - LLM models (folders: models)
  resourcespace - Digital asset management (folders: filestore)
  gitlab        - Git repository hosting (folders: data config logs)
  gitea         - Lightweight Git hosting (folders: data)
  homeassistant - Home automation (folders: config backups)
  
Examples:
  $0 immich upload library profile thumbs encoded-video backups
  $0 paperless media consume export
  $0 navidrome music
  $0 kavita library"
fi

SERVICE="$1"
shift
FOLDERS=("$@")

# Determine volume name and check if it exists
PROJECT_NAME="weekendstack"
VOLUME_NAME=""

case "$SERVICE" in
    immich)
        VOLUME_NAME="${PROJECT_NAME}_immich-nfs-uploads"
        ;;
    paperless)
        VOLUME_NAME="${PROJECT_NAME}_paperless-nfs-media"
        warn "Paperless has multiple volumes. This script handles 'media' folder."
        warn "You may need to run this script multiple times for consume/export volumes."
        ;;
    navidrome)
        VOLUME_NAME="${PROJECT_NAME}_navidrome-nfs-music"
        ;;
    kavita)
        VOLUME_NAME="${PROJECT_NAME}_kavita-nfs-library"
        ;;
    ollama)
        VOLUME_NAME="${PROJECT_NAME}_ollama-nfs-models"
        ;;
    resourcespace)
        VOLUME_NAME="${PROJECT_NAME}_resourcespace-nfs-filestore"
        ;;
    gitlab)
        VOLUME_NAME="${PROJECT_NAME}_gitlab-nfs-data"
        warn "GitLab has multiple volumes. This script handles 'data' folder."
        warn "You may need to run this script multiple times for config/logs volumes."
        ;;
    gitea)
        VOLUME_NAME="${PROJECT_NAME}_gitea-nfs-data"
        ;;
    homeassistant)
        VOLUME_NAME="${PROJECT_NAME}_homeassistant-nfs-config"
        ;;
    *)
        error "Unknown service: $SERVICE
        
Run '$0' without arguments to see available services."
        ;;
esac

info "Service: $SERVICE"
info "Volume:  $VOLUME_NAME"

# Check if volume exists
if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
    error "Volume '$VOLUME_NAME' does not exist.

This likely means:
  1. You haven't uncommented the NFS volume definition in docker-compose file
  2. You haven't started the service with the NFS volume enabled
  3. You haven't configured NFS_SERVER_IP and ${SERVICE^^}_NFS_PATH in .env

Steps to fix:
  1. Edit .env and uncomment/set:
       NFS_SERVER_IP=192.168.2.3
       ${SERVICE^^}_NFS_PATH=/mnt/user/$SERVICE-data
       
  2. Edit docker-compose file and uncomment the NFS volume definition
  
  3. Start the service to create the volume:
       docker compose pull
       docker compose up -d
       
  4. Run this script again"
fi

# Verify NFS mount is working
info "Verifying NFS volume is accessible..."
if ! docker volume inspect "$VOLUME_NAME" | grep -q "nfs"; then
    warn "Volume '$VOLUME_NAME' exists but doesn't appear to be an NFS volume.
This script is designed for NFS volumes. Continuing anyway..."
fi

# Create folders
info "Creating folder structure..."

if [ ${#FOLDERS[@]} -eq 0 ]; then
    # No specific folders requested, just show volume info
    info "No folders specified. Showing volume information:"
    docker run --rm -v "$VOLUME_NAME:/data" alpine ls -la /data
    success "Volume is accessible"
    exit 0
fi

# Build folder creation commands
MKDIR_CMD="mkdir -p"
TOUCH_CMD="touch"

for folder in "${FOLDERS[@]}"; do
    MKDIR_CMD="$MKDIR_CMD /data/$folder"
    TOUCH_CMD="$TOUCH_CMD /data/$folder/.${SERVICE}"
done

# Create folders and marker files
docker run --rm -v "$VOLUME_NAME:/data" alpine sh -c "
    $MKDIR_CMD && \
    $TOUCH_CMD && \
    ls -la /data && \
    echo && \
    echo 'Folder contents:' && \
    ls -la /data/*
" || error "Failed to create folder structure"

success "Folder structure created successfully"

# Show final structure
info "Verifying folder structure..."
docker run --rm -v "$VOLUME_NAME:/data" alpine sh -c "
    echo 'Root directory:' && \
    ls -lah /data && \
    echo && \
    echo 'Subdirectories:' && \
    for dir in /data/*; do
        if [ -d \"\$dir\" ]; then
            echo && \
            echo \"Contents of \$dir:\" && \
            ls -lah \"\$dir\" | head -5
        fi
    done
"

success "NFS volume initialized for $SERVICE"
info "
Next steps:
  1. Verify the folders appear on your NFS server
  2. Update docker-compose.yml to use the NFS volume (uncomment NFS volume mount)
  3. Restart the service: docker compose up -d --force-recreate
  4. Check service logs: docker logs $SERVICE
"
