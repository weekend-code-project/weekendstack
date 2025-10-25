# =============================================================================
# MODULE: Workspace Validation
# =============================================================================
# DESCRIPTION:
#   Runs fast, read-only validation checks after startup. Writes detailed logs
#   to /var/tmp/validation.log and a concise summary to /var/tmp/validation_summary.txt.
#   Never blocks workspace readiness. Can be rerun manually via `validate-workspace`.

data "coder_parameter" "validate_on_start" {
  name         = "validate_on_start"
  display_name = "Validate on Startup"
  description  = "Run non-blocking validation checks after startup."
  type         = "bool"
  default      = true
  mutable      = true
  order        = 95
}

data "coder_parameter" "validate_timeout_s" {
  name         = "validate_timeout_s"
  display_name = "Validation Timeout (s)"
  description  = "Per-check timeout in seconds."
  type         = "number"
  default      = 20
  mutable      = true
  order        = 96
}

locals {
  validate_helper = <<-BASH
    TARGET="/usr/local/bin/validate-workspace"
    if [ ! -w "$(dirname "$TARGET")" ]; then
      TARGET="$HOME/.local/bin/validate-workspace"
      mkdir -p "$(dirname "$TARGET")" || true
    fi
  cat > "$TARGET" <<'EOSH'
  #!/usr/bin/env bash
  set -uo pipefail
    LOG=/var/tmp/validation.log
    SUM=/var/tmp/validation_summary.txt
  TOUT=$${1:-$${VALIDATE_TIMEOUT_S:-20}}

    pass=0; warn=0; fail=0
    start_section() { echo "[$(date +%T)] === $1 ===" | tee -a "$LOG"; }
    ok()   { echo "[OK]   $1"   | tee -a "$LOG"; ((pass++)); }
    warnf(){ echo "[WARN] $1"   | tee -a "$LOG"; ((warn++)); }
    failf(){ echo "[FAIL] $1"   | tee -a "$LOG"; ((fail++)); }

    : > "$LOG"

    # SSH
    start_section "SSH"
    if pgrep -x sshd >/dev/null 2>&1; then ok "sshd running"; else warnf "sshd not found"; fi
    if command -v ss >/dev/null 2>&1 && ss -lnt 2>/dev/null | grep -q ':2222 '; then
      ok "listening on 2222"
    else
      warnf "cannot verify 2222 (ss missing or closed)"
    fi
  [[ -n "$${SSH_PORT:-}" ]] && ok "SSH_PORT=$SSH_PORT" || warnf "SSH_PORT env not set"

    # Docker
    start_section "Docker"
    if command -v docker >/dev/null 2>&1; then
      timeout "$TOUT" docker --version >/dev/null 2>&1 && ok "docker --version" || warnf "docker --version timeout"
      timeout "$TOUT" bash -lc 'docker ps >/dev/null 2>&1' && ok "docker ps" || warnf "docker ps not ready"
      timeout "$TOUT" bash -lc 'docker info >/dev/null 2>&1' && ok "docker info" || warnf "docker info not ready"
      id | grep -q '(docker)' && ok "user in docker group" || warnf "user not in docker group"
    else
      warnf "docker not installed"
    fi

    # Node
    start_section "Node"
    if command -v node >/dev/null 2>&1; then
      node -v | sed 's/^/node /' | tee -a "$LOG" >/dev/null
      ok "node present"
    else
      warnf "node missing"
    fi

    # Git
    start_section "Git"
    if command -v git >/dev/null 2>&1; then
      git --version | tee -a "$LOG" >/dev/null
      git config --get user.name >/dev/null 2>&1 && ok "git user.name set" || warnf "git user.name missing"
      git config --get user.email >/dev/null 2>&1 && ok "git user.email set" || warnf "git user.email missing"
    else
      warnf "git missing"
    fi

    # GitHub CLI
    start_section "GitHub CLI"
    if command -v gh >/dev/null 2>&1; then
      timeout "$TOUT" gh --version >/dev/null 2>&1 && ok "gh --version" || warnf "gh --version timeout"
      proto="$(gh config get git_protocol 2>/dev/null || echo '')"
      if [[ "$proto" == "ssh" ]]; then
        ok "gh git_protocol=ssh"
      else
        warnf "gh git_protocol=$proto"
      fi
      if [[ -f "$HOME/.config/gh/hosts.yml" ]]; then
        ok "gh hosts.yml present"
      else
        warnf "gh hosts.yml missing"
      fi
      timeout "$TOUT" gh auth status -h github.com >/dev/null 2>&1 && ok "gh auth status (github.com)" || warnf "gh not authenticated (github.com)"

      # Direct SSH validation against GitHub (no prompts)
      if command -v ssh >/dev/null 2>&1; then
        out="$(timeout "$TOUT" ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -T git@github.com 2>&1 || true)"
        echo "$out" >> "$LOG"
        if echo "$out" | grep -qi "successfully authenticated"; then
          ok "ssh git@github.com (auth OK)"
        else
          warnf "ssh git@github.com failed"
        fi
      else
        warnf "ssh client not installed"
      fi
    else
      warnf "gh missing"
    fi

    # Node modules persistence
    start_section "Node Modules"
    IFS=',' read -r -a paths <<< "$${NM_PATHS:-.}"
  for p in "$${paths[@]}"; do
      ptrim="$${p//\\n/}"
      [[ -z "$ptrim" ]] && continue
      if [[ -d "$HOME/$ptrim/node_modules" ]]; then
        ok "node_modules present: $ptrim"
      else
        warnf "node_modules missing: $ptrim"
      fi
    done

    # Ports / Traefik
    start_section "Ports"
  if [[ -n "$${PORTS:-}" ]]; then ok "Ports: $PORTS"; else warnf "PORTS env not set"; fi
  if [[ -n "$${PORT:-}" ]]; then ok "Primary port: $PORT"; else warnf "PORT env not set"; fi

    echo "PASS=$pass WARN=$warn FAIL=$fail" | tee "$SUM" >/dev/null
    echo "Summary: PASS=$pass WARN=$warn FAIL=$fail" | tee -a "$LOG" >/dev/null
    exit 0
EOSH
    chmod +x "$TARGET" || true
  BASH

  validate_workspace = <<-BASH
    VALIDATE_TIMEOUT_S=${data.coder_parameter.validate_timeout_s.value}
    export VALIDATE_TIMEOUT_S
    ${local.validate_helper}
    # Resolve helper path again (same logic as above)
    TARGET="/usr/local/bin/validate-workspace"
    if [ -x "$HOME/.local/bin/validate-workspace" ]; then
      TARGET="$HOME/.local/bin/validate-workspace"
    fi
    if [ "${data.coder_parameter.validate_on_start.value}" = "true" ]; then
      echo "[VALIDATE] Running workspace validation (non-blocking)"
      # Use bash to invoke even if exec bit isn't set
      bash "$TARGET" "$VALIDATE_TIMEOUT_S" || true
    else
      echo "[VALIDATE] Skipped on startup (validate_on_start=false)"
    fi
  BASH
}
