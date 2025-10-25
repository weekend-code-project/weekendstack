#!/usr/bin/env bash
# =============================================================================
# cleanup-coder.sh
# =============================================================================
# Find local workspace folders that no longer exist in Coder and move them to
# a trash directory. Defaults to dry-run; pass --apply to execute moves.
#
# Usage:
#   ./cleanup-coder.sh [--apply] [--workspace-dir DIR] [--trash-dir DIR]
#                      [--coder-cmd PATH] [--exclude name1,name2,...]
#
# Defaults:
#   WORKSPACE_DIR: ${WORKSPACE_DIR:-/mnt/workspace/wcp-coder/files/coder/workspace}
#   TRASH_DIR    : ${TRASH_DIR:-/mnt/workspace/wcp-coder/files/coder/_trash}
#
# Requirements:
#   - coder CLI installed and authenticated (coder login <URL>)
#   - jq installed (for robust JSON parsing)
#
# Behavior:
#   - Computes set of current Coder workspace names via CLI
#   - Compares to directories in WORKSPACE_DIR
#   - Any directory not in the Coder list is moved to TRASH_DIR/<name>-<timestamp>
#   - Use --dry-run (default) to preview changes
#
# Exit codes:
#   0 success
#   1 general error
#   2 coder CLI not available / not authenticated
# =============================================================================
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[cleanup]${NC} $*"; }
warn() { echo -e "${YELLOW}[cleanup][warn]${NC} $*"; }
err() { echo -e "${RED}[cleanup][error]${NC} $*" 1>&2; }

# Defaults (can be overridden by env or flags)
WORKSPACE_DIR_DEFAULT="${WORKSPACE_DIR:-/mnt/workspace/wcp-coder/files/coder/workspace}"
TRASH_DIR_DEFAULT="${TRASH_DIR:-/mnt/workspace/wcp-coder/files/coder/_trash}"
CODER_CMD_DEFAULT="${CODER_CMD:-coder}"

APPLY=false
EXCLUDES=""
WORKSPACE_DIR="$WORKSPACE_DIR_DEFAULT"
TRASH_DIR="$TRASH_DIR_DEFAULT"
CODER_CMD="$CODER_CMD_DEFAULT"

usage() {
  cat <<EOF
Usage: $0 [--apply] [--workspace-dir DIR] [--trash-dir DIR] [--coder-cmd PATH] [--exclude name1,name2,...]

Options:
  --apply                Perform moves (default is dry-run)
  --workspace-dir DIR    Root of local workspaces (default: $WORKSPACE_DIR_DEFAULT)
  --trash-dir DIR        Trash directory (default: $TRASH_DIR_DEFAULT)
  --coder-cmd PATH       Path to coder CLI (default: $CODER_CMD_DEFAULT)
  --exclude NAMES        Comma-separated directory names to ignore
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true; shift;;
    --workspace-dir) WORKSPACE_DIR="$2"; shift 2;;
    --trash-dir) TRASH_DIR="$2"; shift 2;;
    --coder-cmd) CODER_CMD="$2"; shift 2;;
    --exclude) EXCLUDES="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "Unknown argument: $1"; usage; exit 1;;
  esac
done

# Validate directories
if [[ ! -d "$WORKSPACE_DIR" ]]; then
  err "Workspace dir not found: $WORKSPACE_DIR"
  exit 1
fi
mkdir -p "$TRASH_DIR"

# Build exclude set
is_excluded() {
  local name="$1"
  [[ -z "$EXCLUDES" ]] && return 1
  IFS=',' read -r -a arr <<< "$EXCLUDES"
  for x in "${arr[@]}"; do
    x="$(echo "$x" | xargs)"
    [[ "$name" == "$x" ]] && return 0
  done
  return 1
}

# Pull workspace names from Coder CLI
get_coder_workspaces() {
  local names_json=""

  # Prefer JSON if supported
  if "$CODER_CMD" workspaces list --help >/dev/null 2>&1; then
    if names_json=$("$CODER_CMD" workspaces list --json 2>/dev/null); then
      echo "$names_json" | jq -r '.[].name' 2>/dev/null && return 0 || true
    fi
  fi

  # Alternate verbs: `ls`
  if "$CODER_CMD" workspaces ls --help >/dev/null 2>&1; then
    if names_json=$("$CODER_CMD" workspaces ls --json 2>/dev/null); then
      echo "$names_json" | jq -r '.[].name' 2>/dev/null && return 0 || true
    fi
  fi

  # Fallback: plain text parsing (first column after header)
  if out=$("$CODER_CMD" workspaces list 2>/dev/null); then
    echo "$out" | awk 'NR>1 {print $1}' | sed '/^$/d' && return 0
  fi

  return 2
}

log "Scanning Coder for workspaces..."
if ! mapfile -t CODER_WS < <(get_coder_workspaces); then
  err "Unable to list Coder workspaces. Ensure coder CLI is installed and you are logged in: coder login <URL>"
  exit 2
fi

# Create an associative set for quick lookup
declare -A CODER_SET
for name in "${CODER_WS[@]}"; do
  [[ -n "$name" ]] && CODER_SET["$name"]=1
done

log "Coder workspaces found: ${#CODER_WS[@]}"

# Find local dirs under WORKSPACE_DIR (names only)
mapfile -t LOCAL_DIRS < <(find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

log "Local workspace dirs found: ${#LOCAL_DIRS[@]} (root=$WORKSPACE_DIR)"

MOVE_LIST=()
for d in "${LOCAL_DIRS[@]}"; do
  # Exclusions
  if is_excluded "$d"; then
    warn "Skipping excluded: $d"
    continue
  fi
  # Skip internal/trash/system dirs
  [[ "$d" == "_trash" ]] && continue

  if [[ -z "${CODER_SET[$d]:-}" ]]; then
    MOVE_LIST+=("$d")
  fi
done

if [[ ${#MOVE_LIST[@]} -eq 0 ]]; then
  log "No stale workspace directories found."
  exit 0
fi

log "Stale dirs to move: ${#MOVE_LIST[@]}"
for d in "${MOVE_LIST[@]}"; do
  src="$WORKSPACE_DIR/$d"
  ts=$(date +%Y%m%d-%H%M%S)
  dest="$TRASH_DIR/${d}-$ts"
  if [[ "$APPLY" == true ]]; then
    log "Moving: $src -> $dest"
    mv "$src" "$dest"
  else
    echo "DRY-RUN: mv '$src' '$dest'"
  fi
done

if [[ "$APPLY" == false ]]; then
  echo ""
  warn "Dry-run only. Re-run with --apply to execute moves."
fi

log "Done."
