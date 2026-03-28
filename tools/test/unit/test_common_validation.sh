#!/bin/bash
# Unit tests for common validation helpers

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"

test_suite_start "Common Validation Helpers"

test_case "validate_email accepts a normal email address"
if validate_email "admin@example.com"; then
    test_pass
else
    test_fail "Expected admin@example.com to be valid"
fi

test_case "validate_email rejects an obviously invalid email"
if ! validate_email "not-an-email"; then
    test_pass
else
    test_fail "Expected not-an-email to be rejected"
fi

test_case "get_env_value preserves values containing trailing equals"
create_temp_env
cat > "$TEST_ENV" <<'EOF'
CLOUDFLARE_TUNNEL_TOKEN=abc123==
EOF

if [[ "$(get_env_value "CLOUDFLARE_TUNNEL_TOKEN" "$TEST_ENV")" == "abc123==" ]]; then
    test_pass
else
    test_fail "Expected get_env_value to preserve base64 padding"
fi

test_suite_end
