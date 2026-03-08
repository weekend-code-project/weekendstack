#!/bin/bash
# harness/lib/snapshot.sh
# Save and restore WeekendStack stack state so tests don't permanently alter it.

SNAPSHOT_BASE_DIR="/tmp/weekendstack-snapshot"

# save_stack_state [LABEL]
# Captures .env, docker-compose.custom.yml, and the list of running containers
# into /tmp/weekendstack-snapshot-{label}-{ts}/
save_stack_state() {
    local label="${1:-default}"
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    SNAPSHOT_DIR="${SNAPSHOT_BASE_DIR}-${label}-${ts}"
    export SNAPSHOT_DIR

    mkdir -p "$SNAPSHOT_DIR"

    local stack_dir="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"

    # Save .env
    if [[ -f "$stack_dir/.env" ]]; then
        cp "$stack_dir/.env" "$SNAPSHOT_DIR/env.bak"
        echo "[SNAPSHOT] Saved .env → $SNAPSHOT_DIR/env.bak"
    else
        echo "[SNAPSHOT] No .env to save"
    fi

    # Save docker-compose.custom.yml
    if [[ -f "$stack_dir/docker-compose.custom.yml" ]]; then
        cp "$stack_dir/docker-compose.custom.yml" "$SNAPSHOT_DIR/docker-compose.custom.yml.bak"
        echo "[SNAPSHOT] Saved docker-compose.custom.yml"
    fi

    # Save running container names
    docker ps --format '{{.Names}}' 2>/dev/null > "$SNAPSHOT_DIR/running-containers.txt"
    local count
    count=$(wc -l < "$SNAPSHOT_DIR/running-containers.txt")
    echo "[SNAPSHOT] Recorded $count running containers"

    echo "$SNAPSHOT_DIR" > "${SNAPSHOT_BASE_DIR}-latest-dir.txt"
    echo "[SNAPSHOT] State saved to: $SNAPSHOT_DIR"
}

# restore_stack_state [SNAPSHOT_DIR]
# Stops the current stack and restores files from the snapshot.
restore_stack_state() {
    local snapshot_dir="${1:-$SNAPSHOT_DIR}"

    if [[ -z "$snapshot_dir" || ! -d "$snapshot_dir" ]]; then
        # Try the latest pointer
        if [[ -f "${SNAPSHOT_BASE_DIR}-latest-dir.txt" ]]; then
            snapshot_dir=$(cat "${SNAPSHOT_BASE_DIR}-latest-dir.txt")
        fi
    fi

    if [[ -z "$snapshot_dir" || ! -d "$snapshot_dir" ]]; then
        echo "[SNAPSHOT] No snapshot directory found — skipping restore"
        return 1
    fi

    local stack_dir="${WEEKENDSTACK_DIR:-/home/ubuntu/weekendstack}"

    echo "[SNAPSHOT] Restoring from: $snapshot_dir"

    # Stop any running containers gracefully
    if [[ -f "$stack_dir/docker-compose.custom.yml" || -f "$stack_dir/docker-compose.yml" ]]; then
        echo "[SNAPSHOT] Stopping current stack..."
        pushd "$stack_dir" >/dev/null
        docker compose down --remove-orphans --timeout 30 2>/dev/null || true
        popd >/dev/null
    fi

    # Restore .env
    if [[ -f "$snapshot_dir/env.bak" ]]; then
        cp "$snapshot_dir/env.bak" "$stack_dir/.env"
        echo "[SNAPSHOT] Restored .env"
    else
        rm -f "$stack_dir/.env"
        echo "[SNAPSHOT] Removed .env (no backup existed)"
    fi

    # Restore docker-compose.custom.yml
    if [[ -f "$snapshot_dir/docker-compose.custom.yml.bak" ]]; then
        cp "$snapshot_dir/docker-compose.custom.yml.bak" "$stack_dir/docker-compose.custom.yml"
        echo "[SNAPSHOT] Restored docker-compose.custom.yml"
    else
        rm -f "$stack_dir/docker-compose.custom.yml"
        echo "[SNAPSHOT] Removed docker-compose.custom.yml (no backup existed)"
    fi

    echo "[SNAPSHOT] Restore complete"
}

# cleanup_snapshot [SNAPSHOT_DIR]
cleanup_snapshot() {
    local snapshot_dir="${1:-$SNAPSHOT_DIR}"
    if [[ -n "$snapshot_dir" && -d "$snapshot_dir" ]]; then
        rm -rf "$snapshot_dir"
        echo "[SNAPSHOT] Cleaned up: $snapshot_dir"
    fi
}
