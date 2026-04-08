#!/bin/bash
# Unit tests for summary auth output.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

export SCRIPT_DIR="$PROJECT_ROOT"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/auth-policy.sh"
source "$PROJECT_ROOT/tools/setup/lib/summary.sh"

save_optional_file() {
    local source_path="$1"
    local backup_path="$2"

    if [[ -f "$source_path" ]]; then
        mkdir -p "$(dirname "$backup_path")"
        cp "$source_path" "$backup_path"
        return 0
    fi

    return 1
}

restore_optional_file() {
    local target_path="$1"
    local backup_path="$2"

    if [[ -f "$backup_path" ]]; then
        cp "$backup_path" "$target_path"
        rm -f "$backup_path"
    else
        rm -f "$target_path"
    fi
}

test_suite_start "Summary Auth Sections"

test_case "summary shows tunnel auth credentials without app default-account claims"
cd "$PROJECT_ROOT"
save_optional_file ".env" "$TEST_DIR/original.env"
save_optional_file "SETUP_SUMMARY.md" "$TEST_DIR/original.SETUP_SUMMARY.md"

cat > .env <<'EOF'
HOST_IP=192.168.2.195
LAB_DOMAIN=lab
BASE_DOMAIN=weekendcodeproject.dev
DOMAIN_MODE=tunnel
DEFAULT_TRAEFIK_AUTH_USER=edge
DEFAULT_TRAEFIK_AUTH_PASS=super-secret-password
COMPOSE_PROFILES=ai,dev,gitea,monitoring
CLOUDFLARE_TUNNEL_ENABLED=true
EOF

if generate_setup_summary ai dev; then
    if grep -q '^### External Tunnel Auth$' SETUP_SUMMARY.md && \
       grep -q '\*\*Username:\*\* `edge`' SETUP_SUMMARY.md && \
       grep -q '\*\*Password:\*\* `super-secret-password`' SETUP_SUMMARY.md && \
       grep -q 'WeekendStack no longer seeds default app accounts automatically' SETUP_SUMMARY.md && \
       ! grep -q 'Seeded Automatically' SETUP_SUMMARY.md && \
       grep -q 'Tunnel-exposed services keep Traefik authentication middleware where configured' SETUP_SUMMARY.md && \
       ! grep -q '^### 1\. Trust Local HTTPS Certificate$' SETUP_SUMMARY.md && \
       ! grep -q '^### 2\. Configure DNS$' SETUP_SUMMARY.md; then
        test_pass
    else
        test_fail "Summary file did not include the expected tunnel auth section"
    fi
else
    test_fail "generate_setup_summary returned non-zero"
fi

restore_optional_file "SETUP_SUMMARY.md" "$TEST_DIR/original.SETUP_SUMMARY.md"
restore_optional_file ".env" "$TEST_DIR/original.env"

test_case "console summary shows tunnel auth credentials for the final setup screen"
cd "$PROJECT_ROOT"
save_optional_file ".env" "$TEST_DIR/original.env.console"

cat > .env <<'EOF'
HOST_IP=192.168.2.195
LAB_DOMAIN=lab
BASE_DOMAIN=weekendcodeproject.dev
DOMAIN_MODE=tunnel
DEFAULT_TRAEFIK_AUTH_USER=edge
DEFAULT_TRAEFIK_AUTH_PASS=super-secret-password
EOF

stub_bin="$TEST_DIR/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/docker" <<'EOF'
#!/bin/sh
if [ "$1" = "compose" ] && [ "$2" = "ps" ]; then
  printf '%s\n' "glance" "traefik"
  exit 0
fi
exit 0
EOF
chmod +x "$stub_bin/docker"

cat > "$stub_bin/clear" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$stub_bin/clear"

summary_output=$(PATH="$stub_bin:$PATH" TERM=xterm display_summary_to_console 2>&1)
if printf '%s' "$summary_output" | grep -q 'External auth credentials:' && \
   printf '%s' "$summary_output" | grep -q 'Username:    edge' && \
   printf '%s' "$summary_output" | grep -q 'Password:    super-secret-password'; then
    test_pass
else
    test_fail "Console summary did not show the tunnel auth credentials"
fi

restore_optional_file ".env" "$TEST_DIR/original.env.console"

test_case "summary prompts users to run configure.sh when tunnel auth is still pending"
cd "$PROJECT_ROOT"
save_optional_file ".env" "$TEST_DIR/original.env.pending"
save_optional_file "SETUP_SUMMARY.md" "$TEST_DIR/original.SETUP_SUMMARY.pending.md"

cat > .env <<'EOF'
HOST_IP=192.168.2.195
LAB_DOMAIN=lab
BASE_DOMAIN=weekendcodeproject.dev
DOMAIN_MODE=tunnel
DEFAULT_TRAEFIK_AUTH_USER=edge
DEFAULT_TRAEFIK_AUTH_PASS=
COMPOSE_PROFILES=core,dev,networking
EOF

if generate_setup_summary core dev; then
    if grep -q 'Run `./configure.sh --tunnel-auth` before exposing tunnel routes' SETUP_SUMMARY.md && \
       grep -q '`./configure.sh --coder-templates`' SETUP_SUMMARY.md && \
       grep -q '`./configure.sh --git-ssh`' SETUP_SUMMARY.md; then
        test_pass
    else
        test_fail "Summary file did not point users at configure.sh when tunnel auth was pending"
    fi
else
    test_fail "generate_setup_summary returned non-zero for pending configure summary"
fi

restore_optional_file "SETUP_SUMMARY.md" "$TEST_DIR/original.SETUP_SUMMARY.pending.md"
restore_optional_file ".env" "$TEST_DIR/original.env.pending"

test_case "ip-mode summary renders direct host URLs instead of stale .lab links"
cd "$PROJECT_ROOT"
save_optional_file ".env" "$TEST_DIR/original.env.ip"
save_optional_file "SETUP_SUMMARY.md" "$TEST_DIR/original.SETUP_SUMMARY.ip.md"
save_optional_file "setup-state.json" "$TEST_DIR/original.setup-state.ip.json"

cat > .env <<'EOF'
HOST_IP=192.168.2.195
LAB_DOMAIN=lab
BASE_DOMAIN=
DOMAIN_MODE=ip
COMPOSE_PROFILES=core
EOF

cat > setup-state.json <<'EOF'
{
  "effective_profiles": ["core"],
  "effective_services": ["glance", "vaultwarden", "speedtest-tracker"],
  "manual_followups": [
    {
      "service": "speedtest-tracker",
      "display_name": "Speedtest Tracker",
      "mode": "manual",
      "url": "http://192.168.2.195:8765",
      "note": "App provides its own initial admin login on first start."
    }
  ],
  "configure_actions": [],
  "health": {
    "services": [
      {"service": "glance", "url": "http://192.168.2.195:8080"},
      {"service": "vaultwarden", "url": "http://192.168.2.195:8082"},
      {"service": "speedtest-tracker", "url": "http://192.168.2.195:8765"}
    ]
  }
}
EOF

if generate_setup_summary core; then
    if grep -q 'http://192.168.2.195:8080' SETUP_SUMMARY.md && \
       grep -q 'http://192.168.2.195:8082' SETUP_SUMMARY.md && \
       ! grep -q 'https://lab' SETUP_SUMMARY.md && \
       ! grep -q 'vault\.lab' SETUP_SUMMARY.md; then
        test_pass
    else
        test_fail "IP-mode summary did not render the expected direct host URLs"
    fi
else
    test_fail "generate_setup_summary returned non-zero for ip-mode summary"
fi

restore_optional_file "setup-state.json" "$TEST_DIR/original.setup-state.ip.json"
restore_optional_file "SETUP_SUMMARY.md" "$TEST_DIR/original.SETUP_SUMMARY.ip.md"
restore_optional_file ".env" "$TEST_DIR/original.env.ip"

test_suite_end
