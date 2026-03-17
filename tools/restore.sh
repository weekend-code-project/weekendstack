#!/usr/bin/env bash
# =============================================================================
# WeekendStack Restore Script
# =============================================================================
# Restores a backup created by tools/backup.sh.
# Interactive — not intended for unattended cron use.
#
# Usage:
#   ./tools/restore.sh [--backup-dir /path] [--from TIMESTAMP] [--no-env] [--yes]
#
# Options:
#   --backup-dir PATH   Directory containing backups (default: ~/weekendstack-backups)
#   --from TIMESTAMP    Restore a specific backup (e.g. 2026-03-17T020000)
#                       Defaults to 'latest' symlink
#   --no-env            Skip restoring the .env file (keep current .env)
#   --yes               Skip confirmation prompts (danger: non-interactive restore)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ARG_BACKUP_DIR=""
ARG_FROM=""
RESTORE_ENV=true
AUTO_YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir) ARG_BACKUP_DIR="$2"; shift 2 ;;
    --from)       ARG_FROM="$2";       shift 2 ;;
    --no-env)     RESTORE_ENV=false;   shift   ;;
    --yes)        AUTO_YES=true;       shift   ;;
    *) echo "Unknown argument: $1" >&2; exit 1  ;;
  esac
done

# ---------------------------------------------------------------------------
# Load .env (to get BACKUP_DIR etc.)
# ---------------------------------------------------------------------------
ENV_FILE="$STACK_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set +e
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]]               && continue
    key="${key// /}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    export "$key"="${value}"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE")
  set -e
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BACKUP_ROOT="${ARG_BACKUP_DIR:-${BACKUP_DIR:-$HOME/weekendstack-backups}}"
STACK_NAME="${COMPOSE_PROJECT_NAME:-weekendstack}"
DATA_DIR="${DATA_BASE_DIR:-$STACK_DIR/data}"
FILES_DIR="${FILES_BASE_DIR:-$STACK_DIR/files}"
CONFIG_DIR="$STACK_DIR/config"
COMPOSE_DIR="$STACK_DIR/compose"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
_c_bold="\033[1m"
_c_green="\033[32m"
_c_yellow="\033[33m"
_c_red="\033[31m"
_c_cyan="\033[36m"
_c_reset="\033[0m"

log()      { echo -e "${_c_bold}[$(date +"%H:%M:%S")]${_c_reset} $*"; }
log_ok()   { echo -e "${_c_green}  ✓${_c_reset} $*"; }
log_warn() { echo -e "${_c_yellow}  ⚠${_c_reset} $*"; }
log_err()  { echo -e "${_c_red}  ✗${_c_reset} $*" >&2; }
log_step() { echo -e "\n${_c_cyan}${_c_bold}━━━ $* ━━━${_c_reset}"; }

confirm() {
  local prompt="$1"
  if $AUTO_YES; then
    log_warn "Auto-confirming: $prompt"
    return 0
  fi
  local response
  read -r -p "$(echo -e "${_c_yellow}${_c_bold}  ? ${_c_reset}${prompt} [y/N] ")" response </dev/tty
  [[ "$response" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# Locate backup
# ---------------------------------------------------------------------------
log_step "WeekendStack Restore"

if [[ ! -d "$BACKUP_ROOT" ]]; then
  log_err "Backup directory not found: $BACKUP_ROOT"
  log_err "Run ./tools/backup.sh first, or specify --backup-dir"
  exit 1
fi

# Resolve which backup to restore
if [[ -n "$ARG_FROM" ]]; then
  RESTORE_PATH="$BACKUP_ROOT/$ARG_FROM"
elif [[ -L "$BACKUP_ROOT/latest" ]]; then
  RESTORE_PATH="$(realpath "$BACKUP_ROOT/latest")"
else
  RESTORE_PATH=""
fi

# If not resolved or doesn't exist, show picker
if [[ -z "$RESTORE_PATH" ]] || [[ ! -d "$RESTORE_PATH" ]]; then
  log "Available backups in $BACKUP_ROOT:"
  echo ""

  mapfile -t backups < <(
    find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d |
    grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}$' |
    sort -r
  )

  if [[ "${#backups[@]}" -eq 0 ]]; then
    log_err "No backups found in $BACKUP_ROOT"
    exit 1
  fi

  for i in "${!backups[@]}"; do
    ts="$(basename "${backups[$i]}")"
    size="$(du -sh "${backups[$i]}" 2>/dev/null | cut -f1)"
    # Check if this is 'latest'
    label=""
    latest_path="$(realpath "$BACKUP_ROOT/latest" 2>/dev/null || true)"
    [[ "${backups[$i]}" == "$latest_path" ]] && label=" (latest)"
    printf "  %2d. %s  [%s]%s\n" "$((i+1))" "$ts" "$size" "$label"
  done

  echo ""
  read -r -p "$(echo -e "${_c_bold}  Select backup [1-${#backups[@]}]:${_c_reset} ")" choice </dev/tty
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
    log_err "Invalid selection"
    exit 1
  fi
  RESTORE_PATH="${backups[$((choice-1))]}"
fi

if [[ ! -d "$RESTORE_PATH" ]]; then
  log_err "Backup not found: $RESTORE_PATH"
  exit 1
fi

RESTORE_TS="$(basename "$RESTORE_PATH")"

# ---------------------------------------------------------------------------
# Read manifest
# ---------------------------------------------------------------------------
MANIFEST="$RESTORE_PATH/manifest.txt"
if [[ -f "$MANIFEST" ]]; then
  source <(grep -E '^[a-z_]+=.*' "$MANIFEST" | grep -v '#')
else
  log_warn "No manifest.txt found — proceeding without metadata"
fi

# ---------------------------------------------------------------------------
# Show what will be restored
# ---------------------------------------------------------------------------
log_step "Restore Plan"
echo ""
echo -e "  ${_c_bold}Backup:${_c_reset}   $RESTORE_TS"
if [[ -f "$MANIFEST" ]]; then
  echo -e "  ${_c_bold}Hostname:${_c_reset} ${hostname:-unknown} (backed up from)"
  echo -e "  ${_c_bold}Profiles:${_c_reset} ${compose_profiles:-unknown}"
fi

vol_count_found="$(find "$RESTORE_PATH/volumes" -name "*.tar.gz" 2>/dev/null | wc -l)"
db_count_found="$(find "$RESTORE_PATH/db-dumps" -name "*.sql.gz" 2>/dev/null | wc -l)"

echo -e "  ${_c_bold}Volumes:${_c_reset}  $vol_count_found tars"
echo -e "  ${_c_bold}DB dumps:${_c_reset} $db_count_found SQL dumps"
echo -e "  ${_c_bold}data/:${_c_reset}    $([[ -f "$RESTORE_PATH/data-dir.tar.gz" ]] && echo "yes" || echo "not in backup")"
echo -e "  ${_c_bold}files/:${_c_reset}   $([[ -f "$RESTORE_PATH/files-dir.tar.gz" ]] && echo "yes" || echo "not in backup")"
echo -e "  ${_c_bold}config/:${_c_reset}  $([[ -f "$RESTORE_PATH/config-dir.tar.gz" ]] && echo "yes" || echo "not in backup")"
echo -e "  ${_c_bold}.env:${_c_reset}     $($RESTORE_ENV && echo "will be restored" || echo "SKIPPED (--no-env)")"
echo ""

log_warn "This will STOP all running services and OVERWRITE current data."
log_warn "This cannot be undone."
echo ""

if ! confirm "Proceed with restore from $RESTORE_TS?"; then
  log "Restore cancelled."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: Stop all services
# ---------------------------------------------------------------------------
log_step "Stopping Services"

cd "$STACK_DIR"

# Collect all running weekendstack containers in case compose is unavailable
running_ctrs="$(docker ps --format '{{.Names}}' 2>/dev/null || true)"

if [[ -f "$STACK_DIR/docker-compose.yml" ]] || [[ -d "$STACK_DIR/compose" ]]; then
  compose_args=()
  # Add all compose files
  for f in "$STACK_DIR/docker-compose.yml" "$STACK_DIR"/compose/docker-compose.*.yml; do
    [[ -f "$f" ]] && compose_args+=(-f "$f")
  done

  stopped=false
  if [[ "${#compose_args[@]}" -gt 0 ]]; then
    if COMPOSE_PROFILES="*" docker compose "${compose_args[@]}" down --timeout 30 2>/dev/null; then
      stopped=true
      log_ok "All services stopped via compose"
    fi
  fi

  if ! $stopped && [[ -n "$running_ctrs" ]]; then
    log_warn "Compose down failed — stopping containers individually"
    echo "$running_ctrs" | xargs -r docker stop --time 15
    log_ok "Containers stopped"
  fi
else
  log_warn "No compose files found — stopping all containers individually"
  if [[ -n "$running_ctrs" ]]; then
    echo "$running_ctrs" | xargs -r docker stop --time 15
    log_ok "Containers stopped"
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Restore named volumes
# ---------------------------------------------------------------------------
log_step "Restoring Named Volumes"

# Map: container name → volume name (for DB containers we prefer SQL dump)
declare -A db_vol_map
db_vol_map["gitea-database"]="${STACK_NAME}_gitea-db-data"
db_vol_map["coder-database"]="${STACK_NAME}_coder-db-data"
db_vol_map["immich-db"]="${STACK_NAME}_immich-db-data"
db_vol_map["paperless-db"]="${STACK_NAME}_paperless-db-data"
db_vol_map["postiz-db"]="${STACK_NAME}_postiz-db-data"
db_vol_map["activepieces-db"]="${STACK_NAME}_activepieces-db-data"
db_vol_map["docmost-db"]="${STACK_NAME}_docmost-db-data"
db_vol_map["n8n-db"]="${STACK_NAME}_n8n-db-data"
db_vol_map["nocodb-db"]="${STACK_NAME}_nocodb-db-data"
db_vol_map["resourcespace-db"]="${STACK_NAME}_resourcespace-db-data"
db_vol_map["librechat-db"]="${STACK_NAME}_librechat-db-data"

# Volumes that have a SQL dump — skip volume tar restore for these
declare -A dumped_vols
for ctr in "${!db_vol_map[@]}"; do
  dump_file="$RESTORE_PATH/db-dumps/${ctr}.sql.gz"
  if [[ -f "$dump_file" ]]; then
    vol="${db_vol_map[$ctr]}"
    dumped_vols["$vol"]="$ctr"
  fi
done

# Restore all volume tars
while IFS= read -r tar_file; do
  [[ -z "$tar_file" ]] && continue
  vol="$(basename "$tar_file" .tar.gz)"

  # Skip DB volumes that will be restored via SQL dump
  if [[ -n "${dumped_vols[$vol]+x}" ]]; then
    log_warn "Skipping volume tar for $vol (SQL dump will be used instead)"
    continue
  fi

  # Recreate volume
  docker volume rm -f "$vol" 2>/dev/null || true
  docker volume create "$vol" >/dev/null

  # Restore contents
  if docker run --rm \
      -v "${vol}:/target" \
      -v "$(dirname "$tar_file"):/backup:ro" \
      alpine \
      tar xzf "/backup/$(basename "$tar_file")" -C /target 2>/dev/null; then
    size="$(du -sh "$tar_file" | cut -f1)"
    log_ok "$vol ← $size"
  else
    log_warn "Failed to restore volume: $vol"
  fi
done < <(find "$RESTORE_PATH/volumes" -name "*.tar.gz" 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# Step 3: Restore databases from SQL dumps
# ---------------------------------------------------------------------------
log_step "Restoring Databases from SQL Dumps"

if [[ "${#dumped_vols[@]}" -eq 0 ]]; then
  log_warn "No SQL dumps found — skipping DB restore (volumes already restored above)"
else
  # We need postgres/mariadb running temporarily to restore SQL dumps.
  # Bring up just the DB containers.
  log "Starting DB containers for restore..."

  compose_args=()
  for f in "$STACK_DIR/docker-compose.yml" "$STACK_DIR"/compose/docker-compose.*.yml; do
    [[ -f "$f" ]] && compose_args+=(-f "$f")
  done

  db_containers=("${!dumped_vols[@]}")

  if [[ "${#compose_args[@]}" -gt 0 ]]; then
    COMPOSE_PROFILES="*" docker compose "${compose_args[@]}" up -d "${db_containers[@]}" 2>/dev/null || \
      log_warn "Could not start DB containers via compose — SQL dump restore will be skipped"
    sleep 8  # wait for DBs to be ready
  fi

  for dump_ctr in "${!dumped_vols[@]}"; do
    # dump_ctr is volume name, dumped_vols[vol]=container_name
    ctr="${dumped_vols[$dump_ctr]}"
    dump_file="$RESTORE_PATH/db-dumps/${ctr}.sql.gz"

    if ! docker ps --format '{{.Names}}' | grep -q "^${ctr}$"; then
      log_warn "$ctr not running — SQL dump for $dump_ctr skipped"
      continue
    fi

    # Detect DB type
    img="$(docker inspect --format '{{.Config.Image}}' "$ctr" 2>/dev/null || true)"

    if [[ "$img" == *"postgres"* ]] || [[ "$img" == *"pgvector"* ]]; then
      pg_user="$(docker exec "$ctr" bash -c 'echo "${POSTGRES_USER:-postgres}"' 2>/dev/null || echo "postgres")"
      if zcat "$dump_file" | docker exec -i "$ctr" psql -U "$pg_user" postgres 2>/dev/null; then
        log_ok "$ctr postgres ← $(du -sh "$dump_file" | cut -f1)"
      else
        log_warn "$ctr postgres restore failed — check container logs"
      fi
    elif [[ "$img" == *"mariadb"* ]] || [[ "$img" == *"mysql"* ]]; then
      db_user="$(docker exec "$ctr" bash -c 'echo "${MYSQL_USER:-root}"' 2>/dev/null || echo "root")"
      db_pass="$(docker exec "$ctr" bash -c 'echo "${MYSQL_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}"' 2>/dev/null || echo "")"
      if zcat "$dump_file" | docker exec -i "$ctr" mysql -u"$db_user" -p"$db_pass" 2>/dev/null; then
        log_ok "$ctr mariadb ← $(du -sh "$dump_file" | cut -f1)"
      else
        log_warn "$ctr mariadb restore failed — check container logs"
      fi
    fi
  done

  # Stop DB containers again — full startup will happen at the end
  log "Stopping DB containers..."
  for ctr in "${db_containers[@]}"; do
    docker stop "$ctr" 2>/dev/null || true
  done
fi

# ---------------------------------------------------------------------------
# Step 4: Restore bind-mount data directories
# ---------------------------------------------------------------------------
log_step "Restoring Data Directories"

if [[ -f "$RESTORE_PATH/data-dir.tar.gz" ]]; then
  rm -rf "$DATA_DIR"
  mkdir -p "$(dirname "$DATA_DIR")"
  tar xzf "$RESTORE_PATH/data-dir.tar.gz" -C "$(dirname "$DATA_DIR")"
  log_ok "data/ restored"
else
  log_warn "data-dir.tar.gz not in backup — skipping"
fi

if [[ -f "$RESTORE_PATH/files-dir.tar.gz" ]]; then
  rm -rf "$FILES_DIR"
  mkdir -p "$(dirname "$FILES_DIR")"
  tar xzf "$RESTORE_PATH/files-dir.tar.gz" -C "$(dirname "$FILES_DIR")"
  log_ok "files/ restored"
else
  log_warn "files-dir.tar.gz not in backup — skipping"
fi

if [[ -f "$RESTORE_PATH/config-dir.tar.gz" ]]; then
  rm -rf "$CONFIG_DIR"
  mkdir -p "$(dirname "$CONFIG_DIR")"
  tar xzf "$RESTORE_PATH/config-dir.tar.gz" -C "$(dirname "$CONFIG_DIR")"
  log_ok "config/ restored"
else
  log_warn "config-dir.tar.gz not in backup — skipping"
fi

if [[ -f "$RESTORE_PATH/compose-config.tar.gz" ]]; then
  rm -rf "$COMPOSE_DIR/config"
  tar xzf "$RESTORE_PATH/compose-config.tar.gz" -C "$COMPOSE_DIR"
  log_ok "compose/config/ restored"
fi

# ---------------------------------------------------------------------------
# Step 5: Restore .env
# ---------------------------------------------------------------------------
if $RESTORE_ENV; then
  log_step "Restoring .env"
  if [[ -f "$RESTORE_PATH/env.bak" ]]; then
    # Keep a copy of the current .env just in case
    [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "${ENV_FILE}.pre-restore"
    cp "$RESTORE_PATH/env.bak" "$ENV_FILE"
    log_ok ".env restored (pre-restore copy saved as .env.pre-restore)"
  else
    log_warn "env.bak not found in backup — .env unchanged"
  fi
else
  log_warn ".env restore skipped (--no-env)"
fi

# ---------------------------------------------------------------------------
# Step 6: Offer to start services
# ---------------------------------------------------------------------------
log_step "Restore Complete"
log_ok "All data restored from $RESTORE_TS"
echo ""

if confirm "Start all services now?"; then
  log "Starting services..."
  source "$ENV_FILE" 2>/dev/null || true

  compose_args=()
  for f in "$STACK_DIR/docker-compose.yml" "$STACK_DIR"/compose/docker-compose.*.yml; do
    [[ -f "$f" ]] && compose_args+=(-f "$f")
  done

  profiles="${COMPOSE_PROFILES:-all}"
  if [[ "${#compose_args[@]}" -gt 0 ]]; then
    COMPOSE_PROFILES="$profiles" docker compose "${compose_args[@]}" up -d
    log_ok "Services started"
  else
    log_warn "No compose files found — start manually with: docker compose up -d"
  fi
else
  log "Start services manually when ready:"
  log "  cd $STACK_DIR && docker compose up -d"
fi

echo ""
