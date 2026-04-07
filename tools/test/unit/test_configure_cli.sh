#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Configure CLI"

test_case "configure.sh status reports pending tunnel and dev actions"
cd "$PROJECT_ROOT"
backup_file ".env"

cat > .env <<'EOF'
HOST_IP=192.168.2.195
LAB_DOMAIN=lab
BASE_DOMAIN=weekendcodeproject.dev
DOMAIN_MODE=tunnel
DEFAULT_TRAEFIK_AUTH_USER=admin
DEFAULT_TRAEFIK_AUTH_PASS=
COMPOSE_PROFILES=core,dev,networking
EOF

configure_output="$(bash ./configure.sh --status 2>&1)"

if printf '%s' "$configure_output" | grep -q './configure.sh --tunnel-auth' && \
   printf '%s' "$configure_output" | grep -q './configure.sh --cloudflare' && \
   printf '%s' "$configure_output" | grep -q './configure.sh --coder-templates' && \
   printf '%s' "$configure_output" | grep -q './configure.sh --git-ssh'; then
    test_pass
else
    test_fail "configure.sh --status did not report the expected pending actions"
fi

restore_file ".env"

test_suite_end
