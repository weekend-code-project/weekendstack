#!/bin/bash
# Unit tests for Gitea auto-install and admin bootstrap wiring.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

AUTH_POLICY_FILE="$PROJECT_ROOT/tools/setup/lib/auth-policy.sh"
COMPOSE_FILE="$PROJECT_ROOT/compose/docker-compose.dev.yml"

test_suite_start "Gitea Bootstrap Wiring"

test_case "Gitea compose config locks initial setup"
if grep -q 'GITEA__security__INSTALL_LOCK: "true"' "$COMPOSE_FILE"; then
    test_pass
else
    test_fail "Expected docker-compose.dev.yml to force Gitea INSTALL_LOCK=true for headless bootstrap"
fi

test_case "Gitea bootstrap uses the installed app config path"
if grep -q '^gitea_admin_exec()' "$AUTH_POLICY_FILE" && \
   grep -q '/usr/local/bin/gitea "\$@" --config /data/gitea/conf/app.ini' "$AUTH_POLICY_FILE" && \
   grep -q '^ensure_gitea_installed()' "$AUTH_POLICY_FILE"; then
    test_pass
else
    test_fail "Expected auth-policy.sh to use Gitea's installed app.ini path and install readiness helper"
fi

test_suite_end
