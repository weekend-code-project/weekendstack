#!/bin/bash
# Unit tests for service auth policy coverage and schema.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

POLICY_FILE="$PROJECT_ROOT/tools/env/mappings/service-auth-policy.json"
METADATA_FILE="$PROJECT_ROOT/tools/env/mappings/service-metadata.json"

test_suite_start "Service Auth Policy Manifest"

test_case "manifest covers every top-level service exactly once"
policy_keys=$(jq -r 'keys[]' "$POLICY_FILE" | sort)
metadata_keys=$(jq -r 'keys[]' "$METADATA_FILE" | sort)

if [[ "$policy_keys" == "$metadata_keys" ]]; then
    test_pass
else
    diff_output=$(comm -3 <(printf '%s\n' "$metadata_keys") <(printf '%s\n' "$policy_keys"))
    test_fail "Manifest keys do not match service metadata:\n$diff_output"
fi

test_case "manifest entries contain required fields"
if jq -e '
    to_entries
    | all(
        .value
        | has("auth_strategy")
        and has("support_tier")
        and has("supports_disable_signup")
        and has("uses_default_admin_user")
        and has("uses_default_admin_email")
        and has("uses_default_admin_password")
        and has("verification_mode")
      )
' "$POLICY_FILE" >/dev/null; then
    test_pass
else
    test_fail "One or more policy entries are missing required fields"
fi

test_case "manifest uses only allowed auth strategies"
if jq -e '
    [ .[] .auth_strategy ]
    | all(. == "env" or . == "cli_init" or . == "manual" or . == "token_only" or . == "access_password" or . == "none")
' "$POLICY_FILE" >/dev/null; then
    test_pass
else
    test_fail "Manifest contains an unsupported auth_strategy"
fi

test_case "documented seeded services have seed env definitions"
if jq -e '
    .["nocodb"].seed_env.NOCODB_ADMIN_EMAIL.literal == "${DEFAULT_ADMIN_EMAIL}"
    and .["paperless-ngx"].seed_env.PAPERLESS_ADMIN_USER.literal == "${DEFAULT_ADMIN_USER}"
    and .["paperless-ngx"].seed_env.PAPERLESS_ACCOUNT_ALLOW_SIGNUPS.literal == "false"
    and .["open-webui"].seed_env.WEBUI_ADMIN_EMAIL.literal == "${DEFAULT_ADMIN_EMAIL}"
    and .["gitea"].seed_env.GITEA_DISABLE_REGISTRATION.literal == "true"
    and .["coder"].bootstrap_handler == "bootstrap_coder_admin"
    and .["filebrowser"].bootstrap_handler == "bootstrap_filebrowser_admin"
' "$POLICY_FILE" >/dev/null; then
    test_pass
else
    test_fail "Expected seeded-service env mappings are missing or incorrect"
fi

test_suite_end
