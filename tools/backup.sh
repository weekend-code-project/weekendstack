#!/usr/bin/env bash
# =============================================================================
# WeekendStack Backup Script
# =============================================================================
# Backs up all Docker named volumes, bind-mount data directories, and config.
# Runs fully unattended — safe for cron.
#
# Usage:
#   ./tools/backup.sh [--backup-dir /path] [--keep N] [--quiet]
#
# Cron example (nightly at 2am):
#   0 2 * * * /home/ubuntu/weekendstack/tools/backup.sh >> /home/ubuntu/weekendstack-backups/backup.log 2>&1
#
# Environment variables (read from .env, can be overridden):
#   BACKUP_DIR      Where to store backups (default: ~/weekendstack-backups)
#   KEEP_BACKUPS    How many backups to keep (default: 7)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ARG_BACKUP_DIR=""
ARG_KEEP=""
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir) ARG_BACKUP_DIR="$2"; shift 2 ;;
    --keep)       ARG_KEEP="$2";       shift 2 ;;
    --quiet)      QUIET=true;           shift   ;;
    *) echo "Unknown argument: $1" >&2; exit 1  ;;
  esac
done

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
ENV_FILE="$STACK_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  # Source only safe KEY=value lines (skip comments, multiline, special chars)
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
KEEP="${ARG_KEEP:-${KEEP_BACKUPS:-7}}"
TIMESTAMP="$(date +"%Y-%m-%dT%H%M%S")"
BACKUP_PATH="$BACKUP_ROOT/$TIMESTAMP"
LOG_FILE="$BACKUP_ROOT/backup.log"
STACK_NAME="${COMPOSE_PROJECT_NAME:-weekendstack}"
DATA_DIR="${DATA_BASE_DIR:-$STACK_DIR/data}"
FILES_DIR="${FILES_BASE_DIR:-$STACK_DIR/files}"
CONFIG_DIR="$STACK_DIR/config"
COMPOSE_DIR="$STACK_DIR/compose"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
IS_TTY=false
[[ -t 1 ]] && IS_TTY=true

_c_bold=""  _c_green=""  _c_yellow=""  _c_red=""  _c_cyan=""  _c_reset=""
if $IS_TTY; then
  _c_bold="\033[1m"
  _c_green="\033[32m"
  _c_yellow="\033[33m"
  _c_red="\033[31m"
  _c_cyan="\033[36m"
  _c_reset="\033[0m"
fi

log()      { echo -e "${_c_bold}[$(date +"%H:%M:%S")]${_c_reset} $*"; }
log_ok()   { echo -e "${_c_green}  ✓${_c_reset} $*"; }
log_warn() { echo -e "${_c_yellow}  ⚠${_c_reset} $*"; }
log_err()  { echo -e "${_c_red}  ✗${_c_reset} $*" >&2; }
log_step() { echo -e "\n${_c_cyan}${_c_bold}━━━ $* ━━━${_c_reset}"; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_ROOT"

log_step "WeekendStack Backup — $TIMESTAMP"
log "Stack dir  : $STACK_DIR"
log "Backup dir : $BACKUP_PATH"
log "Retain     : last $KEEP backups"

if ! command -v docker &>/dev/null; then
  log_err "docker not found. Aborting."
  exit 1
fi

# ---------------------------------------------------------------------------
# Create backup directory structure
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_PATH/volumes"
mkdir -p "$BACKUP_PATH/db-dumps"

# ---------------------------------------------------------------------------
# Helper: dump a postgres container
# ---------------------------------------------------------------------------
dump_postgres() {
  local ctr="$1"
  local outfile="$BACKUP_PATH/db-dumps/${ctr}.sql.gz"

  # Get the postgres superuser from the container environment
  local pg_user
  pg_user="$(docker exec "$ctr" bash -c 'echo "${POSTGRES_USER:-postgres}"' 2>/dev/null || echo "postgres")"

  if docker exec "$ctr" pg_dumpall -U "$pg_user" 2>/dev/null | gzip > "$outfile"; then
    local size; size="$(du -sh "$outfile" | cut -f1)"
    log_ok "$ctr (postgres, user=$pg_user) → $size"
  else
    log_warn "$ctr postgres dump failed — volume tar will be the fallback"
    rm -f "$outfile"
  fi
}

# ---------------------------------------------------------------------------
# Helper: dump a mariadb/mysql container
# ---------------------------------------------------------------------------
dump_mariadb() {
  local ctr="$1"
  local outfile="$BACKUP_PATH/db-dumps/${ctr}.sql.gz"

  local db_user db_pass
  db_user="$(docker exec "$ctr" bash -c 'echo "${MYSQL_USER:-root}"' 2>/dev/null || echo "root")"
  db_pass="$(docker exec "$ctr" bash -c 'echo "${MYSQL_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}"' 2>/dev/null || echo "")"

  if docker exec "$ctr" mysqldump -u"$db_user" -p"$db_pass" --all-databases 2>/dev/null | gzip > "$outfile"; then
    local size; size="$(du -sh "$outfile" | cut -f1)"
    log_ok "$ctr (mariadb, user=$db_user) → $size"
  else
    log_warn "$ctr mariadb dump failed — volume tar will be the fallback"
    rm -f "$outfile"
  fi
}

# ---------------------------------------------------------------------------
# Step 1: Live database dumps (consistent, no stop required)
# ---------------------------------------------------------------------------
log_step "Database Dumps"

# Detect running postgres containers
while IFS= read -r ctr; do
  [[ -z "$ctr" ]] && continue
  img="$(docker inspect --format '{{.Config.Image}}' "$ctr" 2>/dev/null || true)"
  if [[ "$img" == *"postgres"* ]] || [[ "$img" == *"pgvector"* ]]; then
    dump_postgres "$ctr"
  elif [[ "$img" == *"mariadb"* ]] || [[ "$img" == *"mysql"* ]]; then
    dump_mariadb "$ctr"
  fi
done < <(docker ps --format '{{.Names}}')

db_dump_count="$(find "$BACKUP_PATH/db-dumps" -name "*.sql.gz" 2>/dev/null | wc -l)"
if [[ "$db_dump_count" -eq 0 ]]; then
  log_warn "No running DB containers found — only volume tars will be saved"
fi

# ---------------------------------------------------------------------------
# Step 2: Named volume tars
# ---------------------------------------------------------------------------
log_step "Named Volumes"

vol_count=0
while IFS= read -r vol; do
  [[ -z "$vol" ]] && continue
  outfile="$BACKUP_PATH/volumes/${vol}.tar.gz"
  if docker run --rm \
      -v "${vol}:/source:ro" \
      -v "$BACKUP_PATH/volumes:/backup" \
      alpine \
      tar czf "/backup/${vol}.tar.gz" -C /source . 2>/dev/null; then
    size="$(du -sh "$outfile" | cut -f1)"
    log_ok "$vol → $size"
    (( vol_count++ )) || true
  else
    log_warn "Failed to tar volume: $vol"
  fi
done < <(docker volume ls --format '{{.Name}}' | grep "^${STACK_NAME}_")

log "  Saved $vol_count named volumes"

# ---------------------------------------------------------------------------
# Step 3: Bind-mount data directories
# ---------------------------------------------------------------------------
log_step "Data Directories"

_tar_dir() {
  # Usage: _tar_dir <label> <outfile> <parent_dir> <subdir>
  # Uses sudo if direct tar fails (handles root-owned files from containers)
  local label="$1" outfile="$2" parent="$3" subdir="$4"
  [[ -d "$parent/$subdir" ]] || { log_warn "$label not found: $parent/$subdir"; return 0; }
  if tar czf "$outfile" -C "$parent" "$subdir" 2>/dev/null; then
    log_ok "$label → $(du -sh "$outfile" | cut -f1)"
  elif sudo -n tar czf "$outfile" -C "$parent" "$subdir" 2>/dev/null; then
    log_ok "$label (sudo) → $(du -sh "$outfile" | cut -f1)"
  else
    log_warn "$label backup failed — skipping"
  fi
}

_tar_dir "data/"         "$BACKUP_PATH/data-dir.tar.gz"      "$(dirname "$DATA_DIR")"    "$(basename "$DATA_DIR")"
_tar_dir "files/"        "$BACKUP_PATH/files-dir.tar.gz"     "$(dirname "$FILES_DIR")"   "$(basename "$FILES_DIR")"
_tar_dir "config/"       "$BACKUP_PATH/config-dir.tar.gz"    "$(dirname "$CONFIG_DIR")"  "$(basename "$CONFIG_DIR")"
_tar_dir "compose/config" "$BACKUP_PATH/compose-config.tar.gz" "$COMPOSE_DIR"             "config"

# ---------------------------------------------------------------------------
# Step 4: Environment file
# ---------------------------------------------------------------------------
log_step "Environment"

if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$BACKUP_PATH/env.bak"
  # Mask secret values in the log, but keep the file intact
  log_ok ".env saved ($(wc -l < "$ENV_FILE") lines)"
else
  log_warn ".env not found at $ENV_FILE"
fi

# ---------------------------------------------------------------------------
# Step 5: Write manifest
# ---------------------------------------------------------------------------
{
  echo "backup_timestamp=$TIMESTAMP"
  echo "stack_dir=$STACK_DIR"
  echo "stack_name=$STACK_NAME"
  echo "compose_profiles=${COMPOSE_PROFILES:-unknown}"
  echo "selected_profiles=${SELECTED_PROFILES:-unknown}"
  echo "data_dir=$DATA_DIR"
  echo "files_dir=$FILES_DIR"
  echo "volume_count=$vol_count"
  echo "db_dump_count=$db_dump_count"
  echo "docker_version=$(docker --version)"
  echo "hostname=$(hostname -f 2>/dev/null || hostname)"
  echo ""
  echo "# Volumes backed up:"
  docker volume ls --format '{{.Name}}' | grep "^${STACK_NAME}_" | sed 's/^/  /'
  echo ""
  echo "# DB dumps:"
  find "$BACKUP_PATH/db-dumps" -name "*.sql.gz" -printf '  %f\n' 2>/dev/null || true
} > "$BACKUP_PATH/manifest.txt"

log_ok "manifest.txt written"

# ---------------------------------------------------------------------------
# Step 6: Update 'latest' symlink
# ---------------------------------------------------------------------------
ln -sfn "$TIMESTAMP" "$BACKUP_ROOT/latest"
log_ok "latest → $TIMESTAMP"

# ---------------------------------------------------------------------------
# Step 7: Prune old backups (keep last N)
# ---------------------------------------------------------------------------
log_step "Pruning Old Backups"

# List all timestamped backup dirs sorted oldest first, skip symlinks
mapfile -t all_backups < <(
  find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d |
  grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}$' |
  sort
)

total="${#all_backups[@]}"
to_delete=$(( total - KEEP ))

if [[ "$to_delete" -gt 0 ]]; then
  for (( i=0; i<to_delete; i++ )); do
    old="${all_backups[$i]}"
    rm -rf "$old"
    log_ok "Removed old backup: $(basename "$old")"
  done
else
  log "  Nothing to prune ($total / $KEEP slots used)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total_size="$(du -sh "$BACKUP_PATH" | cut -f1)"
log_step "Backup Complete"
log "  Location  : $BACKUP_PATH"
log "  Total size: $total_size"
log "  Volumes   : $vol_count"
log "  DB dumps  : $db_dump_count"
log ""
