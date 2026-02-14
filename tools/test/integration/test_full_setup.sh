#!/bin/bash
# Integration test for full setup flow

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "Full Setup Integration"

# Test 1: Setup can generate .env non-interactively
test_case "Setup generates .env in quick mode"
cd "$PROJECT_ROOT"
backup_file ".env"

# Run setup in quick mode which should be non-interactive
if timeout 30 bash -c '
    export SETUP_MODE=quick
    source tools/setup/lib/common.sh
    source tools/setup/lib/env-generator.sh
    generate_env_quick core networking
' 2>&1 | grep -q "Quick environment setup complete"; then
    test_pass
else
    test_fail "Quick setup did not complete"
fi

restore_file ".env"

# Test 2: Validation doesn't hang or exit prematurely
test_case "Validation script completes without hanging"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

# Run validation with timeout
if timeout 10 ./tools/validate-env.sh >/dev/null 2>&1; then
    validation_exit=$?
else
    validation_exit=124  # timeout exit code
fi

if [ $validation_exit -ne 124 ]; then
    test_pass
else
    test_fail "Validation script timed out (hung)"
fi

restore_file ".env"

# Test 3: .env generation with custom values works
test_case ".env updates with custom admin password"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

# Simulate what setup.sh does - update admin password
source tools/setup/lib/env-generator.sh
update_env_var "DEFAULT_ADMIN_PASSWORD" "my_custom_password123" ".env"

# Check if password was set
password=$(grep "^DEFAULT_ADMIN_PASSWORD=" .env | head -1 | cut -d'=' -f2)

if [ "$password" = "my_custom_password123" ]; then
    test_pass
else
    test_fail "Password not updated correctly, got: $password"
fi

restore_file ".env"

# Test 4: Validation passes after complete setup
test_case "Validation passes with properly configured .env"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

# Set required values that might be empty
source tools/setup/lib/env-generator.sh
update_env_var "HOST_IP" "192.168.1.100" ".env"
update_env_var "DEFAULT_ADMIN_PASSWORD" "SecurePass123!" ".env"

# Run validation
validation_output=$(./tools/validate-env.sh 2>&1)

if echo "$validation_output" | grep -q "All checks passed\|not critical"; then
    test_pass
else
    test_fail "Validation failed with configured values"
fi

restore_file ".env"

test_suite_end
