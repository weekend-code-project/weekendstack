#!/bin/bash
# Regression tests for tunnel-only Traefik auth and manual app-account setup.

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

SETUP_FILE="$PROJECT_ROOT/setup.sh"
ENV_GENERATOR="$PROJECT_ROOT/tools/setup/lib/env-generator.sh"
SUMMARY_FILE="$PROJECT_ROOT/tools/setup/lib/summary.sh"
VALIDATE_ENV="$PROJECT_ROOT/tools/validate-env.sh"
AI_COMPOSE="$PROJECT_ROOT/compose/docker-compose.ai.yml"
DEV_COMPOSE="$PROJECT_ROOT/compose/docker-compose.dev.yml"
CORE_COMPOSE="$PROJECT_ROOT/compose/docker-compose.core.yml"
PRODUCTIVITY_COMPOSE="$PROJECT_ROOT/compose/docker-compose.productivity.yml"
RESOURCESPACE_ENTRYPOINT="$PROJECT_ROOT/config/resourcespace/entrypoint.sh"

test_suite_start "Tunnel Auth Only Setup"

test_case "setup no longer runs service admin bootstrap tasks after startup"
if ! grep -q 'run_auth_bootstrap_tasks' "$SETUP_FILE"; then
    test_pass
else
    test_fail "setup.sh should not run shared service-admin bootstrap tasks"
fi

test_case "env generator prompts for tunnel auth instead of shared app admins"
if grep -q 'Traefik auth username' "$ENV_GENERATOR" && \
   grep -q 'only for the Traefik basic-auth popup' "$ENV_GENERATOR" && \
   ! grep -q 'Customize admin credentials' "$ENV_GENERATOR"; then
    test_pass
else
    test_fail "env-generator should prompt only for tunnel auth credentials"
fi

test_case "setup uses tunnel auth credentials for htpasswd generation"
if grep -q 'DEFAULT_TRAEFIK_AUTH_USER' "$SETUP_FILE" && \
   grep -q 'DEFAULT_TRAEFIK_AUTH_PASS' "$SETUP_FILE" && \
   ! grep -q 'DEFAULT_ADMIN_PASSWORD' "$SETUP_FILE"; then
    test_pass
else
    test_fail "setup.sh should build htpasswd from tunnel auth credentials only"
fi

test_case "setup exposes a tunnel-auth-only recovery path"
if grep -q -- '--tunnel-auth-only' "$SETUP_FILE" && \
   grep -q 'run_tunnel_auth_setup_only' "$SETUP_FILE"; then
    test_pass
else
    test_fail "setup.sh should expose a tunnel-auth-only recovery command"
fi

test_case "tunnel-auth-only flow refreshes Traefik auth assets"
if grep -q 'refresh_traefik_auth_assets' "$SETUP_FILE" && \
   grep -q 'restart_traefik_if_running' "$SETUP_FILE"; then
    test_pass
else
    test_fail "tunnel-auth-only should regenerate auth assets and apply them to Traefik"
fi

test_case "manual account services keep signup or setup enabled by default"
if grep -q 'ENABLE_SIGNUP=${ENABLE_SIGNUP:-True}' "$AI_COMPOSE" && \
   grep -q 'GITEA__service__DISABLE_REGISTRATION: ${GITEA_DISABLE_REGISTRATION:-false}' "$DEV_COMPOSE"; then
    test_pass
else
    test_fail "Open WebUI and Gitea should default to manual account creation"
fi

test_case "shared admin env seeding is removed from seeded services"
if ! grep -q 'APP_ADMIN_EMAIL' "$CORE_COMPOSE" && \
   ! grep -q 'NC_ADMIN_EMAIL' "$PRODUCTIVITY_COMPOSE" && \
   ! grep -q 'PAPERLESS_ADMIN_USER' "$PRODUCTIVITY_COMPOSE" && \
   ! grep -q 'DEFAULT_ADMIN_USER: ${DEFAULT_ADMIN_USER}' "$PRODUCTIVITY_COMPOSE"; then
    test_pass
else
    test_fail "Compose files should not auto-seed default app accounts"
fi

test_case "resourcespace no longer auto-creates an admin account"
if ! grep -q 'default_admin_username' "$RESOURCESPACE_ENTRYPOINT" && \
   grep -q 'Complete account setup in the web UI' "$RESOURCESPACE_ENTRYPOINT"; then
    test_pass
else
    test_fail "ResourceSpace entrypoint should no longer inject a default admin account"
fi

test_case "summary and validation no longer require shared app admin credentials"
if ! grep -q 'DEFAULT_ADMIN_PASSWORD' "$SUMMARY_FILE" && \
   ! grep -q '"DEFAULT_ADMIN_PASSWORD"' "$VALIDATE_ENV"; then
    test_pass
else
    test_fail "summary/validation should not depend on shared app admin credentials"
fi

test_suite_end
