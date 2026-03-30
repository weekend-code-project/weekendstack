#!/bin/bash
# Unit tests for summary auth classification output.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

export SCRIPT_DIR="$PROJECT_ROOT"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/auth-policy.sh"
source "$PROJECT_ROOT/tools/setup/lib/summary.sh"

test_suite_start "Summary Auth Sections"

test_case "summary lists seeded and manual services from resolved COMPOSE_PROFILES"
cd "$PROJECT_ROOT"
backup_file ".env"
backup_file "SETUP_SUMMARY.md"

cat > .env <<'EOF'
HOST_IP=192.168.2.195
LAB_DOMAIN=lab
BASE_DOMAIN=weekendcodeproject.dev
DOMAIN_MODE=tunnel
DEFAULT_ADMIN_USER=jesse
DEFAULT_ADMIN_EMAIL=jesse@example.com
DEFAULT_ADMIN_PASSWORD=super-secret-password
COMPOSE_PROFILES=ai,dev,gitea,monitoring
CLOUDFLARE_TUNNEL_ENABLED=true
EOF

if generate_setup_summary ai dev; then
    if grep -q '^### Seeded Automatically$' SETUP_SUMMARY.md && \
       grep -q '\*\*Open WebUI\*\*' SETUP_SUMMARY.md && \
       grep -q '\*\*Gitea\*\*' SETUP_SUMMARY.md && \
       grep -q '^### Manual First Admin Still Required$' SETUP_SUMMARY.md && \
       grep -q '\*\*Coder\*\*' SETUP_SUMMARY.md && \
       grep -q 'Tunnel-exposed services keep Traefik authentication middleware where configured' SETUP_SUMMARY.md; then
        test_pass
    else
        test_fail "Summary file did not include the expected auth sections and service classifications"
    fi
else
    test_fail "generate_setup_summary returned non-zero"
fi

restore_file "SETUP_SUMMARY.md"
restore_file ".env"

test_suite_end
