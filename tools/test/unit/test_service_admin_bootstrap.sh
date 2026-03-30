#!/bin/bash
# Regression tests for admin bootstrap wiring in currently supported services.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

AUTH_POLICY_FILE="$PROJECT_ROOT/tools/setup/lib/auth-policy.sh"
PRODUCTIVITY_COMPOSE="$PROJECT_ROOT/compose/docker-compose.productivity.yml"
FILEBROWSER_INIT="$PROJECT_ROOT/config/filebrowser/init-filebrowser.sh.example"
DIRECTORY_CREATOR="$PROJECT_ROOT/tools/setup/lib/directory-creator.sh"
SETUP_FILE="$PROJECT_ROOT/setup.sh"
ENV_GENERATOR="$PROJECT_ROOT/tools/setup/lib/env-generator.sh"
VALIDATE_ENV="$PROJECT_ROOT/tools/validate-env.sh"

test_suite_start "Service Admin Bootstrap Wiring"

test_case "Coder bootstrap handler exists"
if grep -q '^bootstrap_coder_admin()' "$AUTH_POLICY_FILE" && \
   grep -q '/opt/coder server create-admin-user' "$AUTH_POLICY_FILE" && \
   grep -q 'CODER_PG_CONNECTION_URL is not set' "$AUTH_POLICY_FILE"; then
    test_pass
else
    test_fail "Expected auth-policy.sh to bootstrap Coder admins via coder server create-admin-user"
fi

test_case "File Browser bootstrap uses the shared admin username and persistent database"
if grep -q 'DEFAULT_ADMIN_USER: ${DEFAULT_ADMIN_USER}' "$PRODUCTIVITY_COMPOSE" && \
   grep -q 'FB_DATABASE: /config/filebrowser.db' "$PRODUCTIVITY_COMPOSE" && \
   grep -q 'ADMIN_USER="${DEFAULT_ADMIN_USER:-admin}"' "$FILEBROWSER_INIT" && \
   grep -q 'DB="${FB_DATABASE:-/config/filebrowser.db}"' "$FILEBROWSER_INIT"; then
    test_pass
else
    test_fail "Expected File Browser to receive DEFAULT_ADMIN_USER and use /config/filebrowser.db for admin bootstrap"
fi

test_case "File Browser bootstrap repairs runtime ownership after admin setup"
if grep -q 'chown "\$RUNTIME_OWNER" "\$DB"' "$FILEBROWSER_INIT" && \
   grep -q 'chown abc:users "\$DB"' "$AUTH_POLICY_FILE"; then
    test_pass
else
    test_fail "Expected File Browser bootstrap to hand the database back to the abc runtime user"
fi

test_case "File Browser bootstrap script is made executable before startup"
if grep -q 'chmod +x "$stack_dir/config/filebrowser/init-filebrowser.sh"' "$DIRECTORY_CREATOR" && \
   grep -q 'chmod +x "$SCRIPT_DIR/config/filebrowser/init-filebrowser.sh"' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected setup to ensure init-filebrowser.sh is executable before starting File Browser"
fi

test_case "setup and validate-env use the shared admin password validator"
if grep -q 'shared_admin_password_rules_text' "$PROJECT_ROOT/tools/setup/lib/common.sh" && \
   grep -q 'validate_shared_admin_password "$admin_password"' "$ENV_GENERATOR" && \
   grep -q 'validate_shared_admin_password "$DEFAULT_ADMIN_PASS"' "$VALIDATE_ENV"; then
    test_pass
else
    test_fail "Expected setup and validate-env to share one admin password validation policy"
fi

test_case "Gitea bootstrap validates the shared admin username before create"
if grep -q 'validate_shared_admin_username "$admin_user" "true"' "$AUTH_POLICY_FILE" && \
   grep -q 'Admin username' "$ENV_GENERATOR"; then
    test_pass
else
    test_fail "Expected Gitea bootstrap to reject invalid shared admin usernames before trying to create the user"
fi

test_suite_end
