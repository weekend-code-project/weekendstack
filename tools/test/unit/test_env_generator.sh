#!/bin/bash
# Unit tests for env generation

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"
source "$PROJECT_ROOT/tools/setup/lib/common.sh"

test_suite_start "Environment Generator"

# Test 1: update_env_var with simple value
test_case "update_env_var handles simple values"
create_temp_env
echo "TEST_VAR=old_value" > "$TEST_ENV"

update_env_var "TEST_VAR" "new_value" "$TEST_ENV"

if grep -q "^TEST_VAR=new_value$" "$TEST_ENV"; then
    test_pass
else
    test_fail "Expected TEST_VAR=new_value, got: $(grep TEST_VAR $TEST_ENV)"
fi

# Test 2: update_env_var with special characters (dollar signs, braces, slashes)
test_case "update_env_var handles special characters"
create_temp_env
echo "PATH_VAR=/old/path" > "$TEST_ENV"

update_env_var "PATH_VAR" '${CONFIG_BASE_DIR}/ssh' "$TEST_ENV"

if grep -q '^PATH_VAR=\${CONFIG_BASE_DIR}/ssh$' "$TEST_ENV"; then
    test_pass
else
    test_fail "Special characters not preserved: $(grep PATH_VAR $TEST_ENV)"
fi

# Test 3: update_env_var with spaces
test_case "update_env_var handles values with spaces"
create_temp_env
echo "DESC=old" > "$TEST_ENV"

update_env_var "DESC" "value with spaces" "$TEST_ENV"

if grep -q "^DESC=value with spaces$" "$TEST_ENV"; then
    test_pass
else
    test_fail "Spaces not preserved: $(grep DESC $TEST_ENV)"
fi

# Test 4: update_env_var with slashes in paths
test_case "update_env_var handles paths with slashes"
create_temp_env
echo "WORKSPACE_DIR=/old" > "$TEST_ENV"

update_env_var "WORKSPACE_DIR" "/mnt/workspace" "$TEST_ENV"

if grep -q "^WORKSPACE_DIR=/mnt/workspace$" "$TEST_ENV"; then
    test_pass
else
    test_fail "Slashes not preserved: $(grep WORKSPACE_DIR $TEST_ENV)"
fi

# Test 5: update_env_var preserves other lines
test_case "update_env_var preserves other lines"
create_temp_env
cat > "$TEST_ENV" << 'EOF'
VAR1=value1
VAR2=value2
VAR3=value3
EOF

update_env_var "VAR2" "new_value" "$TEST_ENV"

if grep -q "^VAR1=value1$" "$TEST_ENV" && \
   grep -q "^VAR2=new_value$" "$TEST_ENV" && \
   grep -q "^VAR3=value3$" "$TEST_ENV"; then
    test_pass
else
    test_fail "Other lines not preserved"
fi

# Test 6: Template generation
test_case "env-template-gen.sh creates .env"
cd "$PROJECT_ROOT"
backup_file ".env"

if ./tools/env-template-gen.sh >/dev/null 2>&1; then
    if [ -f ".env" ]; then
        test_pass
    else
        test_fail ".env not created"
    fi
else
    test_fail "env-template-gen.sh failed"
fi
restore_file ".env"

# Test 7: Generated secrets are unique
test_case "Generated secrets are random/unique"
cd "$PROJECT_ROOT"
backup_file ".env"

env_one="$TEST_DIR/generated-1.env"
env_two="$TEST_DIR/generated-2.env"

./tools/env-template-gen.sh .env.example "$env_one" >/dev/null 2>&1
secret1=$(grep "^DEFAULT_DB_PASS=" "$env_one" | cut -d'=' -f2)

./tools/env-template-gen.sh .env.example "$env_two" >/dev/null 2>&1
secret2=$(grep "^DEFAULT_DB_PASS=" "$env_two" | cut -d'=' -f2)

if [ "$secret1" != "$secret2" ] && [ -n "$secret1" ] && [ -n "$secret2" ]; then
    test_pass
else
    test_fail "Secrets not random (secret1=$secret1, secret2=$secret2)"
fi
restore_file ".env"

# Test 8: N8N variables with numbers get generated
test_case "Variables with numbers (N8N) are generated"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

if grep -q "^N8N_DB_PASS=[a-f0-9]" .env; then
    if ! grep -q "N8N_DB_PASS=.*<GENERATE>" .env; then
        test_pass
    else
        test_fail "N8N_DB_PASS still has <GENERATE> tag"
    fi
else
    test_fail "N8N_DB_PASS not generated with hex value"
fi
restore_file ".env"

# Test 9: No remaining <GENERATE> tags after generation
test_case "All <GENERATE> tags are replaced"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

generate_count=$(grep -c "<GENERATE>" .env 2>/dev/null || true)
if [ -z "$generate_count" ]; then
    generate_count=0
fi

if [ "$generate_count" -eq 0 ]; then
    test_pass
else
    test_fail "Found $generate_count remaining <GENERATE> tags"
fi
restore_file ".env"

# Test 10: Tunnel auth is deferred to configure.sh and not auto-generated in .env
test_case "DEFAULT_TRAEFIK_AUTH_PASS stays blank until configure.sh runs"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1
auth_pass=$(grep "^DEFAULT_TRAEFIK_AUTH_PASS=" .env | cut -d'=' -f2)

if [ -z "$auth_pass" ]; then
    test_pass
else
    test_fail "DEFAULT_TRAEFIK_AUTH_PASS should stay blank until configure.sh sets it: $auth_pass"
fi
restore_file ".env"

# Test 11: No duplicate variable definitions in .env.example
test_case "No duplicate variables in .env.example"
cd "$PROJECT_ROOT"

# Extract all variable names (lines starting with A-Z and containing =)
duplicates=$(grep -E '^[A-Z0-9_]+=' .env.example | cut -d'=' -f1 | sort | uniq -d)

if [ -z "$duplicates" ]; then
    test_pass
else
    test_fail "Found duplicate variables: $duplicates"
fi

# Test 12: Generated .env has no duplicate variable definitions
test_case "Generated .env has no duplicate variables"
cd "$PROJECT_ROOT"
backup_file ".env"

./tools/env-template-gen.sh >/dev/null 2>&1

duplicates=$(grep -E '^[A-Z0-9_]+=' .env | cut -d'=' -f1 | sort | uniq -d)

if [ -z "$duplicates" ]; then
    test_pass
else
    test_fail "Found duplicate variables in .env: $duplicates"
fi
restore_file ".env"

# Test 13: Access mode flow is a single top-level chooser
test_case "env generator exposes a single tunnel local ip access chooser"
ENV_GENERATOR_FILE="$PROJECT_ROOT/tools/setup/lib/env-generator.sh"

if grep -q 'How should you access WeekendStack\?' "$ENV_GENERATOR_FILE" && \
   grep -q '1) Tunnel' "$ENV_GENERATOR_FILE" && \
   grep -q '2) Local Domain' "$ENV_GENERATOR_FILE" && \
   grep -q '3) Local IP' "$ENV_GENERATOR_FILE" && \
   grep -q 'DNS for local domain\?' "$ENV_GENERATOR_FILE"; then
    test_pass
else
    test_fail "Expected env generator to provide a single access-mode chooser with a local-domain DNS follow-up"
fi

test_suite_end
