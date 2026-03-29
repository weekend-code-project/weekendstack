#!/bin/bash
# Unit tests for Glance URL generation based on access mode

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/glance-generator.sh"

test_suite_start "Glance Generator"

test_case "tunnel access mode generates public domain links"
create_temp_env
cat > "$TEST_DIR/tunnel.env" <<'EOF'
HOST_IP=192.168.2.195
BASE_DOMAIN=weekendcodeproject.dev
LAB_DOMAIN=lab
DOMAIN_MODE=tunnel
COMPOSE_PROFILES=all,networking,pihole
EOF

generate_glance_config "$TEST_DIR/tunnel-glance.yml" "$TEST_DIR/tunnel.env" >/dev/null 2>&1

if grep -q 'url: https://traefik.weekendcodeproject.dev' "$TEST_DIR/tunnel-glance.yml" && \
   grep -q 'url: https://pihole.weekendcodeproject.dev' "$TEST_DIR/tunnel-glance.yml"; then
    test_pass
else
    test_fail "Expected tunnel mode to generate BASE_DOMAIN links in Glance"
fi

test_case "local access mode generates .lab links"
cat > "$TEST_DIR/local.env" <<'EOF'
HOST_IP=192.168.2.195
BASE_DOMAIN=localhost
LAB_DOMAIN=lab
DOMAIN_MODE=local
COMPOSE_PROFILES=all,networking,pihole
EOF

generate_glance_config "$TEST_DIR/local-glance.yml" "$TEST_DIR/local.env" >/dev/null 2>&1

if grep -q 'url: https://traefik.lab' "$TEST_DIR/local-glance.yml" && \
   grep -q 'url: https://pihole.lab' "$TEST_DIR/local-glance.yml"; then
    test_pass
else
    test_fail "Expected local mode to generate .lab links in Glance"
fi

test_case "ip access mode generates HOST_IP links"
cat > "$TEST_DIR/ip.env" <<'EOF'
HOST_IP=192.168.2.195
BASE_DOMAIN=localhost
LAB_DOMAIN=lab
DOMAIN_MODE=ip
COMPOSE_PROFILES=all,networking,pihole
EOF

generate_glance_config "$TEST_DIR/ip-glance.yml" "$TEST_DIR/ip.env" >/dev/null 2>&1

if grep -q 'url: http://192.168.2.195:8081' "$TEST_DIR/ip-glance.yml" && \
   grep -q 'url: http://192.168.2.195:8088/admin' "$TEST_DIR/ip-glance.yml"; then
    test_pass
else
    test_fail "Expected ip mode to generate HOST_IP links in Glance"
fi

test_suite_end
