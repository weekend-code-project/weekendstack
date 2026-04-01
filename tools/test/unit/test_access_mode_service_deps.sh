#!/bin/bash
# Unit tests for access-mode-specific init container behavior.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Access Mode Service Dependencies"

test_case "networking profile no longer auto-runs cert-generator"
NETWORKING_COMPOSE="$PROJECT_ROOT/compose/docker-compose.networking.yml"
if awk '
    /^  cert-generator:/ { in_block=1; next }
    in_block && /^  [^[:space:]].*:/ { in_block=0 }
    in_block && /- networking/ { found=1 }
    END { exit(found ? 1 : 0) }
' "$NETWORKING_COMPOSE"; then
    test_pass
else
    test_fail "cert-generator is still attached to the networking profile"
fi

test_case "tunnel mode does not schedule local cert or Pi-hole init containers"
backup_file "$PROJECT_ROOT/.env"
cat > "$PROJECT_ROOT/.env" <<'EOF'
DOMAIN_MODE=tunnel
COMPOSE_PROFILES=all,networking,external
EOF

source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/service-deps.sh"

init_containers=$(get_init_containers_for_profiles all networking external)
if [[ "$init_containers" != *"cert-generator"* ]] && [[ "$init_containers" != *"pihole-dnsmasq-init"* ]]; then
    test_pass
else
    test_fail "Tunnel mode still scheduled local-only init containers: $init_containers"
fi

restore_file "$PROJECT_ROOT/.env"

test_suite_end
