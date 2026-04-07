#!/bin/bash
# Unit tests for validation

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Environment Validation"

# Test 1: Validation passes with good .env
test_case "Validation passes with complete .env"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

# Set required values
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=192.168.1.100/m' .env
perl -0pi -e 's%^TZ=.*%TZ=America/New_York%m' .env

if ./tools/validate-env.sh >/dev/null 2>&1; then
    test_pass
else
    test_fail "Validation should pass with complete .env"
fi
restore_file ".env"

# Test 2: Validation catches weak tunnel auth passwords
test_case "Validation detects weak tunnel auth passwords"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1
perl -0pi -e 's/^DOMAIN_MODE=.*/DOMAIN_MODE=tunnel/m' .env
perl -0pi -e 's/^DEFAULT_TRAEFIK_AUTH_PASS=.*/DEFAULT_TRAEFIK_AUTH_PASS=password123/m' .env
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=192.168.1.100/m' .env

if ! ./tools/validate-env.sh 2>&1 | grep -q "Weak password detected"; then
    test_fail "Should detect weak password 'password123'"
else
    test_pass
fi
restore_file ".env"

# Test 2b: Validation warns when tunnel auth is intentionally pending
test_case "Validation warns when tunnel auth is pending configure"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1
cp .env.example .env
perl -0pi -e 's/^DOMAIN_MODE=.*/DOMAIN_MODE=tunnel/m' .env
perl -0pi -e 's/^DEFAULT_TRAEFIK_AUTH_PASS=.*/DEFAULT_TRAEFIK_AUTH_PASS=/m' .env
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=192.168.1.100/m' .env

if ./tools/validate-env.sh 2>&1 | grep -q "./configure.sh --tunnel-auth"; then
    test_pass
else
    test_fail "Should warn that tunnel auth is pending configure.sh"
fi
restore_file ".env"

# Test 3: Validation catches empty required fields
test_case "Validation detects empty required fields"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=/m' .env

if ./tools/validate-env.sh 2>&1 | grep -q "Required field is empty"; then
    test_pass
else
    test_fail "Should detect empty HOST_IP"
fi
restore_file ".env"

# Test 4: Validation handles inline comments correctly
test_case "Validation strips inline comments correctly"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1
# Replace HOST_IP line with one that has an inline comment
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=192.168.1.50                    # My IP/m' .env

# Run validation and check that it processed the IP correctly
validation_output=$(./tools/validate-env.sh 2>&1)
if echo "$validation_output" | grep -q "HOST_IP format valid"; then
    test_pass
else
    test_fail "Failed to validate HOST_IP with inline comment"
fi
restore_file ".env"

# Test 5: Validation catches remaining <GENERATE> tags
test_case "Validation detects unfilled <GENERATE> tags"
cd "$PROJECT_ROOT"
backup_file ".env"

cp .env.example .env
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=192.168.1.100/m' .env

if ./tools/validate-env.sh 2>&1 | grep -q "GENERATE"; then
    test_pass
else
    test_fail "Should detect remaining <GENERATE> tags"
fi
restore_file ".env"

# Test 6: Validation accepts valid IP addresses
test_case "Validation accepts valid IP format"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1
perl -0pi -e 's/^HOST_IP=.*/HOST_IP=10.0.0.50/m' .env

if ./tools/validate-env.sh 2>&1 | grep -q "HOST_IP format valid"; then
    test_pass
else
    test_fail "Should accept valid IP 10.0.0.50"
fi
restore_file ".env"

# Test 7: Validation without .env file fails gracefully
test_case "Validation handles missing .env file"
cd "$PROJECT_ROOT"
backup_file ".env"
rm -f .env

if ./tools/validate-env.sh 2>&1 | grep -q ".env file not found"; then
    test_pass
else
    test_fail "Should report missing .env file"
fi
restore_file ".env"

test_suite_end
