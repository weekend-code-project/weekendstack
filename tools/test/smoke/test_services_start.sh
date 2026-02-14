#!/bin/bash
# Smoke test to verify basic stack functionality

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Service Startup Smoke Tests"

# Test 1: Docker daemon is running
test_case "Docker daemon is running"
if docker info >/dev/null 2>&1; then
    test_pass
else
    test_fail "Docker daemon not running"
    test_suite_end
fi

# Test 2: Docker Compose V2 is available
test_case "Docker Compose V2 is available"
if docker compose version >/dev/null 2>&1; then
    test_pass
else
    test_fail "Docker Compose V2 not available"
fi

# Test 3: Required Docker networks can be created
test_case "Can create Docker networks"
test_network="weekendstack-test-$$"
if docker network create "$test_network" >/dev/null 2>&1; then
    docker network rm "$test_network" >/dev/null 2>&1
    test_pass
else
    test_fail "Cannot create Docker networks"
fi

# Test 4: Can pull a test image
test_case "Can pull Docker images"
if docker pull hello-world:latest >/dev/null 2>&1; then
    test_pass
else
    test_fail "Cannot pull Docker images"
fi

# Test 5: .env file exists if stack is configured
test_case ".env file exists (or stack not yet configured)"
cd "$PROJECT_ROOT"
if [ -f ".env" ]; then
    test_pass
else
    test_skip "No .env file - stack not configured yet"
fi

test_suite_end
