#!/bin/bash
# Unit tests for shared auth policy helper behavior.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

export SCRIPT_DIR="$PROJECT_ROOT"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/auth-policy.sh"
source "$PROJECT_ROOT/tools/setup/lib/env-generator.sh"

test_suite_start "Service Auth Policy Helpers"

test_case "auth policy resolves all services for all profile"
resolved_count=$(auth_policy_resolve_services all | wc -l | tr -d ' ')
expected_count=$(jq -r 'keys | length' "$PROJECT_ROOT/tools/env/mappings/service-auth-policy.json")

if [[ "$resolved_count" == "$expected_count" ]]; then
    test_pass
else
    test_fail "Expected $expected_count services for all profile, got $resolved_count"
fi

test_case "auth policy resolves only top-level services from profile map"
resolved_services=$(auth_policy_resolve_services monitoring | sort | tr '\n' ' ')

if [[ "$resolved_services" == *"wud"* ]] && [[ "$resolved_services" == *"uptime-kuma"* ]] && [[ "$resolved_services" != *"guacd"* ]]; then
    test_pass
else
    test_fail "Expected monitoring auth services without support containers, got: $resolved_services"
fi

test_case "manifest-driven env propagation seeds service-specific vars"
create_temp_env
cat > "$TEST_ENV" <<'EOF'
DEFAULT_ADMIN_USER=jesse
DEFAULT_ADMIN_EMAIL=jesse@example.com
DEFAULT_ADMIN_PASSWORD=pass
EOF

auth_policy_apply_seed_env_defaults "$TEST_ENV"

if grep -q '^NOCODB_ADMIN_EMAIL=jesse@example.com$' "$TEST_ENV" && \
   grep -q '^NOCODB_ADMIN_PASSWORD=passStack24!$' "$TEST_ENV" && \
   grep -q '^WEBUI_ADMIN_EMAIL=jesse@example.com$' "$TEST_ENV" && \
   grep -q '^WEBUI_ADMIN_PASSWORD=pass$' "$TEST_ENV" && \
   grep -q '^WEBUI_ADMIN_NAME=jesse$' "$TEST_ENV" && \
   grep -q '^ENABLE_SIGNUP=False$' "$TEST_ENV" && \
   grep -q '^PAPERLESS_ACCOUNT_ALLOW_SIGNUPS=false$' "$TEST_ENV" && \
   grep -q '^GITEA_DISABLE_REGISTRATION=true$' "$TEST_ENV"; then
    test_pass
else
    test_fail "Expected manifest-driven env propagation did not populate the target variables"
fi

test_case "token-only services still bucket as manual"
if [[ "$(auth_policy_bucket_for_service vaultwarden)" == "manual" ]]; then
    test_pass
else
    test_fail "Vaultwarden should be treated as manual account creation, not seeded"
fi

test_suite_end
