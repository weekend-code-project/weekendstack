#!/bin/bash
# Unit tests for profile selector

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Profile Selector"

# Test 1: Profile compose files exist
test_case "All profile compose files exist"
cd "$PROJECT_ROOT"

expected_profiles="core networking monitoring productivity dev ai media"
missing=0

for profile in $expected_profiles; do
    compose_file="compose/docker-compose.${profile}.yml"
    if [ ! -f "$compose_file" ]; then
        echo "    Missing: $compose_file"
        missing=$((missing + 1))
    fi
done

if [ $missing -eq 0 ]; then
    test_pass
else
    test_fail "$missing compose files missing"
fi

# Test 2: Can extract profiles from .env file
test_case "Can extract profiles from .env file"
cd "$PROJECT_ROOT"
backup_file ".env"

cat > .env << 'EOF'
COMPOSE_PROFILES=core,networking,dev
OTHER_VAR=value
EOF

# Simple profile extraction logic
if grep -q "^COMPOSE_PROFILES=" .env; then
    profiles=$(grep "^COMPOSE_PROFILES=" .env | cut -d'=' -f2 | tr ',' ' ')
    if echo "$profiles" | grep -q "core" && \
       echo "$profiles" | grep -q "networking" && \
       echo "$profiles" | grep -q "dev"; then
        test_pass
    else
        test_fail "Failed to extract profiles: $profiles"
    fi
else
    test_fail "COMPOSE_PROFILES not found"
fi

restore_file ".env"

# Test 3: Profile selector script has valid syntax
test_case "Profile selector script syntax is valid"
if bash -n "$PROJECT_ROOT/tools/setup/lib/profile-selector.sh"; then
    test_pass
else
    test_fail "profile-selector.sh has syntax errors"
fi

test_suite_end
