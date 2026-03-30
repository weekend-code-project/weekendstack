#!/bin/bash
# Unit tests for setup.sh start/stop/restart service command wiring

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

SETUP_FILE="$PROJECT_ROOT/setup.sh"

test_suite_start "Setup Service Commands"

test_case "start_services delegates to profile-aware startup"
if grep -q 'start_services_with_profiles "${profiles\[@\]}"' "$SETUP_FILE" && \
   grep -q 'No COMPOSE_PROFILES found in .env. Run ./setup.sh first.' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected start_services to require COMPOSE_PROFILES and delegate to start_services_with_profiles"
fi

test_case "stop_services removes orphans"
if grep -q 'docker compose down --remove-orphans' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected stop_services to use docker compose down --remove-orphans"
fi

test_case "restart_services reuses stop and start helpers"
if grep -q 'stop_services || return 1' "$SETUP_FILE" && \
   grep -q '^    start_services$' "$SETUP_FILE"; then
    test_pass
else
    test_fail "Expected restart_services to reuse stop_services and start_services"
fi

test_suite_end
