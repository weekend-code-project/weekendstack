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

test_case "validate_shared_admin_username accepts a cross-service safe username"
if validate_shared_admin_username "weekendstack" "true"; then
    test_pass
else
    test_fail "Expected weekendstack to pass shared admin username validation"
fi

test_case "validate_shared_admin_username rejects Gitea reserved admin"
if ! validate_shared_admin_username "admin" "true" && [[ "$SHARED_ADMIN_USERNAME_ERROR" == *"Gitea reserves"* ]]; then
    test_pass
else
    test_fail "Expected admin to be rejected when Gitea is enabled"
fi

test_case "validate_shared_admin_username rejects unsupported characters"
if ! validate_shared_admin_username "Jesse.Freeman" && [[ "$SHARED_ADMIN_USERNAME_ERROR" == *"lowercase letters"* ]]; then
    test_pass
else
    test_fail "Expected mixed-case or dotted usernames to be rejected by the shared username validator"
fi

test_case "validate_shared_admin_password accepts a service-safe custom password"
if validate_shared_admin_password "WeekendStack42"; then
    test_pass
else
    test_fail "Expected WeekendStack42 to pass shared admin password validation"
fi

test_case "validate_shared_admin_password rejects short passwords"
if ! validate_shared_admin_password "Short123" && [[ "$SHARED_ADMIN_PASSWORD_ERROR" == *"at least 12 characters"* ]]; then
    test_pass
else
    test_fail "Expected short passwords to be rejected with a minimum-length error"
fi

test_case "validate_shared_admin_password rejects unsupported characters"
if ! validate_shared_admin_password "WeekendStack42#" && [[ "$SHARED_ADMIN_PASSWORD_ERROR" == *"unsupported characters"* ]]; then
    test_pass
else
    test_fail "Expected # to be rejected for shared admin passwords"
fi

test_case "validate_shared_admin_password allows an empty password when auto-generate is enabled"
if validate_shared_admin_password "" "yes"; then
    test_pass
else
    test_fail "Expected blank shared admin password to be allowed for auto-generation"
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
