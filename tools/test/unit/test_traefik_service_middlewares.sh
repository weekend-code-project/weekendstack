#!/bin/bash
# Unit tests for Traefik service middleware generation by access mode.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

export SCRIPT_DIR="$PROJECT_ROOT"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/auth-policy.sh"

test_suite_start "Traefik Service Middlewares"

test_case "tunnel mode keeps basic auth middlewares"
create_temp_env
cat > "$TEST_ENV" <<'EOF'
DOMAIN_MODE=tunnel
EOF

generate_traefik_service_middlewares "$TEST_ENV" "$TEST_DIR/tunnel.yml"

if grep -q 'basicAuth:' "$TEST_DIR/tunnel.yml" && ! grep -q 'X-WeekendStack-Access-Mode: local' "$TEST_DIR/tunnel.yml"; then
    test_pass
else
    test_fail "Tunnel mode should generate real basic auth middlewares"
fi

test_case "local domain mode disables basic auth wrappers"
cat > "$TEST_ENV" <<'EOF'
DOMAIN_MODE=local
EOF

generate_traefik_service_middlewares "$TEST_ENV" "$TEST_DIR/local.yml"

if ! grep -q 'basicAuth:' "$TEST_DIR/local.yml" && grep -q 'X-WeekendStack-Access-Mode: local' "$TEST_DIR/local.yml"; then
    test_pass
else
    test_fail "Local mode should generate no-op local headers instead of basic auth"
fi

test_case "local IP mode also disables basic auth wrappers"
cat > "$TEST_ENV" <<'EOF'
DOMAIN_MODE=ip
EOF

generate_traefik_service_middlewares "$TEST_ENV" "$TEST_DIR/ip.yml"

if ! grep -q 'basicAuth:' "$TEST_DIR/ip.yml" && grep -q 'X-WeekendStack-Access-Mode: local' "$TEST_DIR/ip.yml"; then
    test_pass
else
    test_fail "IP mode should generate no-op local headers instead of basic auth"
fi

test_suite_end
