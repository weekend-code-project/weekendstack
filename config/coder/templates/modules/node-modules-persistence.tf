# =============================================================================
# MODULE: Node Modules Persistence
# =============================================================================
# Provides a script to bind-mount ~/.persist/node_modules/<path> over selected
# node_modules directories inside the workspace, and installs deps if needed.

locals {
  nm_paths = [
    for p in split(",", coalesce(data.coder_parameter.node_modules_paths.value, "")) :
    trimspace(p)
    if length(trimspace(p)) > 0
  ]
}

locals {
  setup_node_modules_persistence = <<-EOT
    if [ -n "$NM_PATHS" ]; then
      IFS=',' read -r -a __paths <<< "$NM_PATHS"
      for P in "$${__paths[@]}"; do
        P="$(echo "$P" | xargs)"; [ -z "$P" ] && continue
        P="$${P%/}"; P="$${P#/}"           # trim slashes
        P="workspace/$P/node_modules"       # ensure we target node_modules folder
        TARGET="$HOME/$P"
        SAFE="$(echo "$P" | sed 's#/#_#g')"

        mkdir -p "$HOME/.persist/node_modules/$SAFE" "$TARGET"
        if mountpoint -q "$TARGET"; then sudo umount "$TARGET" || true; fi
        sudo mount --bind "$HOME/.persist/node_modules/$SAFE" "$TARGET"
        echo "[PERSISTENCE] Bound $TARGET -> $HOME/.persist/node_modules/$SAFE"

        D="$(dirname "$TARGET")"
        if [ -f "$D/package.json" ]; then
          lockfile="$TARGET/.install.lock"
          sentinel="$TARGET/.deps_ready"
          lockhash="$(cat "$D"/pnpm-lock.yaml "$D"/yarn.lock "$D"/package-lock.json 2>/dev/null | sha256sum | awk '{print $1}')"
          current="$(awk '{print $1}' "$sentinel" 2>/dev/null || true)"
          (
            flock 9
            if [ "$lockhash" != "$current" ] || [ -z "$(ls -A "$TARGET" 2>/dev/null)" ]; then
              echo "[NPM] Installing deps in $D"
              if command -v pnpm >/dev/null 2>/dev/null && [ -f "$D/pnpm-lock.yaml" ]; then
                (cd "$D" && pnpm install)
              elif command -v yarn >/dev/null 2>/dev/null && [ -f "$D/yarn.lock" ]; then
                (cd "$D" && yarn install)
              elif [ -f "$D/package-lock.json" ]; then
                (cd "$D" && npm ci || npm install)
              else
                (cd "$D" && npm install)
              fi
              echo "$lockhash" > "$sentinel"
            else
              echo "[NPM] $D up-to-date; skipping"
            fi
          ) 9>"$lockfile"
        fi
      done
    fi
  EOT
}
