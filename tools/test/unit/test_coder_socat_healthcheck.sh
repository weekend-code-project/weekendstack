#!/bin/bash
# Unit tests for the Coder socat Docker proxy healthcheck

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Coder Socat Healthcheck"

test_case "socat healthcheck targets IPv4 loopback instead of localhost"
if grep -q 'test: \["CMD", "nc", "-z", "127.0.0.1", "2375"\]' "$PROJECT_ROOT/compose/docker-compose.dev.yml" && \
   ! grep -q 'test: \["CMD", "nc", "-z", "localhost", "2375"\]' "$PROJECT_ROOT/compose/docker-compose.dev.yml"; then
    test_pass
else
    test_fail "Expected socat healthcheck to target 127.0.0.1 instead of localhost"
fi

test_suite_end
