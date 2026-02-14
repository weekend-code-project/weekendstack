#!/bin/bash
# ============================================================================
# Test Suite: UID/GID Configuration Validation
# ============================================================================
# Tests that PUID/PGID values are correctly set and validated
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../test_helpers.sh"

test_suite_start "UID/GID Configuration" "unit"

# Test 1: Default UID/GID from current user
test_case "Current user UID/GID is detected correctly"
current_uid=$(id -u)
current_gid=$(id -g)

if [[ $current_uid =~ ^[0-9]+$ ]] && [[ $current_gid =~ ^[0-9]+$ ]]; then
    test_pass "UID=$current_uid, GID=$current_gid detected"
else
    test_fail "Failed to detect user UID/GID"
fi

# Test 2: UID/GID set in env file
test_case "PUID/PGID correctly set in .env by quick mode"
backup_file "$PROJECT_ROOT/.env"

source "$PROJECT_ROOT/tools/setup/lib/common.sh"
source "$PROJECT_ROOT/tools/setup/lib/env-generator.sh"

export SCRIPT_DIR="$PROJECT_ROOT"
if generate_env_quick "core" >/dev/null 2>&1; then
    env_puid=$(grep "^PUID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
    env_pgid=$(grep "^PGID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
    
    if [[ "$env_puid" == "$current_uid" ]] && [[ "$env_pgid" == "$current_gid" ]]; then
        test_pass "PUID/PGID set to current user ($current_uid/$current_gid)"
    else
        test_fail "PUID/PGID mismatch. Expected: $current_uid/$current_gid, Got: $env_puid/$env_pgid"
    fi
else
    test_fail "Failed to generate .env"
fi

# Test 3: UID/GID validation range
test_case "UID/GID values are within valid range"
if [[ $env_puid -ge 0 ]] && [[ $env_puid -le 65535 ]]; then
    if [[ $env_pgid -ge 0 ]] && [[ $env_pgid -le 65535 ]]; then
        test_pass "PUID/PGID within valid range (0-65535)"
    else
        test_fail "PGID out of range: $env_pgid"
    fi
else
    test_fail "PUID out of range: $env_puid"
fi

# Test 4: Custom UID/GID update
test_case "Custom UID/GID can be set via update_env_var"
update_env_var "PUID" "1001" "$PROJECT_ROOT/.env"
update_env_var "PGID" "1001" "$PROJECT_ROOT/.env"

custom_puid=$(grep "^PUID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
custom_pgid=$(grep "^PGID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)

if [[ "$custom_puid" == "1001" ]] && [[ "$custom_pgid" == "1001" ]]; then
    test_pass "Custom PUID/PGID updated successfully"
else
    test_fail "Failed to update custom PUID/PGID. Got: $custom_puid/$custom_pgid"
fi

# Test 5: Root UID (0) handling
test_case "Root UID (0) is accepted but should warn in production"
update_env_var "PUID" "0" "$PROJECT_ROOT/.env"
update_env_var "PGID" "0" "$PROJECT_ROOT/.env"

root_puid=$(grep "^PUID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
if [[ "$root_puid" == "0" ]]; then
    test_pass "Root UID (0) can be set (valid for testing)"
else
    test_fail "Failed to set root UID"
fi

# Test 6: UID/GID persistence across updates
test_case "PUID/PGID values persist when updating other variables"
update_env_var "PUID" "1234" "$PROJECT_ROOT/.env"
update_env_var "PGID" "5678" "$PROJECT_ROOT/.env"

# Update a different variable
update_env_var "HOST_IP" "192.168.1.100" "$PROJECT_ROOT/.env"

# Check PUID/PGID are unchanged
final_puid=$(grep "^PUID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)
final_pgid=$(grep "^PGID=" "$PROJECT_ROOT/.env" | cut -d'=' -f2)

if [[ "$final_puid" == "1234" ]] && [[ "$final_pgid" == "5678" ]]; then
    test_pass "PUID/PGID persisted across other updates"
else
    test_fail "PUID/PGID changed unexpectedly: $final_puid/$final_pgid"
fi

restore_file "$PROJECT_ROOT/.env"

test_suite_end
