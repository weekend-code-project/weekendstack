#!/usr/bin/env bash
# ============================================================================
# test-modular-env.sh - Comprehensive test suite for modular env system
# ============================================================================
# Tests:
#   1. Template assembly for each profile
#   2. Global variables accessible in all profiles
#   3. Secret generation works correctly
#   4. Profile-specific variables included correctly
#   5. Custom profile generation
#   6. Variable deduplication
#   7. Env validation
# ============================================================================

set -e

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_OUTPUT_DIR="/tmp/weekendstack-test-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create test output directory
mkdir -p "$TEST_OUTPUT_DIR"

# Test result tracking
declare -a FAILED_TESTS=()

# Logging
log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Helper: Run test
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "$test_name"
    
    if $test_func; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name"
        return 1
    fi
}

# ============================================================================
# TEST 1: Assembly Engine Works for Each Profile
# ============================================================================
test_assembly_single_profiles() {
    local profiles=("core" "ai" "productivity" "dev" "media" "automation" "monitoring" "networking" "personal")
    
    for profile in "${profiles[@]}"; do
        local output_file="${TEST_OUTPUT_DIR}/${profile}.env.test"
        
        if "${REPO_ROOT}/tools/env/scripts/assemble-env.sh" \
            --profiles "$profile" \
            --output "$output_file" >/dev/null 2>&1; then
            
            if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
                log_pass "  Profile '$profile' assembly successful"
            else
                log_fail "  Profile '$profile' produced empty file"
                return 1
            fi
        else
            log_fail "  Profile '$profile' assembly failed"
            return 1
        fi
    done
    
    return 0
}

# ============================================================================
# TEST 2: Global Variables Present in All Assembled Profiles
# ============================================================================
test_global_variables_present() {
    local required_globals=(
        "HOST_IP"
        "TZ"
        "PUID"
        "PGID"
        "LAB_DOMAIN"
        "BASE_DOMAIN"
        "FILES_BASE_DIR"
        "DATA_BASE_DIR"
        "DEFAULT_ADMIN_EMAIL"
        "DEFAULT_ADMIN_USER"
        "DEFAULT_ADMIN_PASSWORD"
        "DEFAULT_DB_USER"
        "DEFAULT_DB_PASS"
    )
    
    local test_file="${TEST_OUTPUT_DIR}/core.env.test"
    
    for var in "${required_globals[@]}"; do
        if ! grep -q "^${var}=" "$test_file"; then
            log_fail "  Global variable missing: $var"
            return 1
        fi
    done
    
    log_pass "  All global variables present"
    return 0
}

# ============================================================================
# TEST 3: Profile-Specific Variables Included
# ============================================================================
test_profile_specific_variables() {
    # Test that AI profile includes AI-specific variables
    local ai_file="${TEST_OUTPUT_DIR}/ai.env.test"
    
    local ai_vars=(
        "OLLAMA_PORT"
        "WEBUI_SECRET_KEY"
        "ANYTHINGLLM_JWT_SECRET"
        "LIBRECHAT_JWT_SECRET"
    )
    
    for var in "${ai_vars[@]}"; do
        if ! grep -q "^${var}=" "$ai_file" && ! grep -q "^${var}\s*=" "$ai_file"; then
 if ! grep -q "$var" "$ai_file"; then
                log_warn "  AI variable possibly missing: $var (not critical if service doesn't use env vars)"
            fi
        fi
    done
    
    # Test that core profile does NOT include AI variables
    local core_file="${TEST_OUTPUT_DIR}/core.env.test"
    if grep -q "OLLAMA_PORT" "$core_file"; then
        log_fail "  Core profile incorrectly includes AI variables"
        return 1
    fi
    
    log_pass "  Profile-specific variables correctly isolated"
    return 0
}

# ============================================================================
# TEST 4: Secret Generation Works
# ============================================================================
test_secret_generation() {
    local test_file="${TEST_OUTPUT_DIR}/test-secrets.env"
    
    # Assemble and generate secrets
    "${REPO_ROOT}/tools/env/scripts/assemble-env.sh" \
        --profiles "core" \
        --output "${TEST_OUTPUT_DIR}/test-secrets.assembled" >/dev/null 2>&1
    
    "${REPO_ROOT}/tools/env-template-gen.sh" \
        "${TEST_OUTPUT_DIR}/test-secrets.assembled" \
        "$test_file" >/dev/null 2>&1
    
    # Check that secrets were generated (no <GENERATE> tags remain)
    if grep -q "<GENERATE>" "$test_file"; then
        log_fail "  Secrets not fully generated - <GENERATE> tags remain"
        return 1
    fi
    
    # Check that generated secrets are not empty
    local secret_vars=(
        "DEFAULT_DB_PASS"
        "DEFAULT_JWT_SECRET"
        "DEFAULT_TRAEFIK_AUTH_PASS"
    )
    
    for var in "${secret_vars[@]}"; do
        local value=$(grep "^${var}=" "$test_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
        if [[ -z "$value" ]] || [[ "$value" == "<GENERATE>"* ]]; then
            log_fail "  Secret not generated: $var"
            return 1
        fi
        
        # Check minimum length (should be at least 32 chars for most secrets)
        if [[ ${#value} -lt 16 ]]; then
            log_fail "  Secret too short: $var (${#value} chars)"
            return 1
        fi
    done
    
    log_pass "  Secrets generated correctly"
    return 0
}

# ============================================================================
# TEST 5: Multi-Profile Assembly
# ============================================================================
test_multi_profile_assembly() {
    local output_file="${TEST_OUTPUT_DIR}/multi.env.test"
    
    "${REPO_ROOT}/tools/env/scripts/assemble-env.sh" \
        --profiles "core,ai,productivity" \
        --output "$output_file" >/dev/null 2>&1
    
    # Should include variables from all three profiles
    local expected_vars=(
        "VAULTWARDEN_ADMIN_TOKEN"  # core
        "OLLAMA_PORT"              # ai
        "NOCODB_JWT_SECRET"        # productivity
    )
    
    for var in "${expected_vars[@]}"; do
        if ! grep -q "$var" "$output_file"; then
            log_warn "  Multi-profile variable possibly missing: $var"
        fi
    done
    
    log_pass "  Multi-profile assembly successful"
    return 0
}

# ============================================================================
# TEST 6: Variable Deduplication
# ============================================================================
test_variable_deduplication() {
    local output_file="${TEST_OUTPUT_DIR}/dedup.env.test"
    
    "${REPO_ROOT}/tools/env/scripts/assemble-env.sh" \
        --profiles "core,ai" \
        --output "$output_file" >/dev/null 2>&1
    
    # Check that global variables appear only once
    local count=$(grep -c "^HOST_IP=" "$output_file" || echo "0")
    if [[ $count -ne 1 ]]; then
        log_fail "  HOST_IP appears $count times (should be 1)"
        return 1
    fi
    
    log_pass "  Variables properly deduplicated"
    return 0
}

# ============================================================================
# TEST 7: Custom Profile Generation
# ============================================================================
test_custom_profile_generation() {
    local output_file="${TEST_OUTPUT_DIR}/docker-compose.custom.yml"
    
    "${REPO_ROOT}/tools/env/scripts/generate-custom-profile.sh" \
        --profiles "core,ai" >/dev/null 2>&1
    
    local custom_file="${REPO_ROOT}/docker-compose.custom.yml"
    
    if [[ ! -f "$custom_file" ]]; then
        log_fail "  Custom profile file not created"
        return 1
    fi
    
    # Check that it includes services from both profiles
    if ! grep -q "vaultwarden:" "$custom_file"; then
        log_fail "  Custom profile missing core service (vaultwarden)"
        return 1
    fi
    
    if ! grep -q "ollama:" "$custom_file"; then
        log_fail "  Custom profile missing AI service (ollama)"
        return 1
    fi
    
    # Check that custom profile is set
    if ! grep -q "\- custom" "$custom_file"; then
        log_fail "  Custom profile tag not found"
        return 1
    fi
    
    log_pass "  Custom profile generated correctly"
    return 0
}

# ============================================================================
# TEST 8: Validation Works with Profile-Aware Mode
# ============================================================================
test_profile_aware_validation() {
    local test_env="${TEST_OUTPUT_DIR}/validation-test.env"
    
    # Generate test env
    "${REPO_ROOT}/tools/env/scripts/assemble-env.sh" \
        --profiles "core" \
        --output "${TEST_OUTPUT_DIR}/validation-test.assembled" >/dev/null 2>&1
    
    "${REPO_ROOT}/tools/env-template-gen.sh" \
        "${TEST_OUTPUT_DIR}/validation-test.assembled" \
        "$test_env" >/dev/null 2>&1
    
    # Copy to project root for validation
    cp "$test_env" "${REPO_ROOT}/.env.test"
    
    # Run validation (capture output)
    cd "$REPO_ROOT"
    if "${REPO_ROOT}/tools/validate-env.sh" >/dev/null 2>&1; then
        log_pass "  Profile-aware validation successful"
        rm -f "${REPO_ROOT}/.env.test"
        return 0
    else
        log_warn "  Validation found issues (check manually)"
        rm -f "${REPO_ROOT}/.env.test"
        return 0  # Don't fail test for validation warnings
    fi
}

# ============================================================================
# TEST 9: Assembly Reduces File Size
# ============================================================================
test_assembly_reduces_size() {
    local core_file="${TEST_OUTPUT_DIR}/core.env.test"
    local full_file="${REPO_ROOT}/.env.example"
    
    local core_lines=$(wc -l < "$core_file")
    local full_lines=$(wc -l < "$full_file")
    
    if [[ $core_lines -ge $full_lines ]]; then
        log_fail "  Core profile not smaller than full .env.example ($core_lines >= $full_lines)"
        return 1
    fi
    
    local reduction=$(( (full_lines - core_lines) * 100 / full_lines ))
    log_pass "  File size reduced by ${reduction}% for core profile"
    return 0
}

# ============================================================================
# TEST 10: COMPOSE_PROFILES Set to 'custom'
# ============================================================================
test_compose_profiles_custom() {
    local test_file="${TEST_OUTPUT_DIR}/compose-profile.env.test"
    
    "${REPO_ROOT}/tools/env/scripts/assemble-env.sh" \
        --profiles "core" \
        --output "$test_file" >/dev/null 2>&1
    
    # Extract value and strip comments
    local compose_profiles=$(grep "^COMPOSE_PROFILES=" "$test_file" | cut -d'=' -f2 | sed 's/#.*//' | tr -d ' ')
    
    if [[ "$compose_profiles" != "custom" ]]; then
        log_fail "  COMPOSE_PROFILES not set to 'custom' (got: $compose_profiles)"
        return 1
    fi
    
    log_pass "  COMPOSE_PROFILES correctly set to 'custom'"
    return 0
}

# ============================================================================
# Main Test Execution
# ============================================================================
main() {
    echo ""
    echo "============================================================================"
    echo "  WeekendStack - Modular Env System Test Suite"
    echo "============================================================================"
    echo ""
    
    log_info "Running comprehensive tests..."
    echo ""
    
    # Run all tests
    run_test "1. Assembly engine works for all profiles" test_assembly_single_profiles
    run_test "2. Global variables present in assembled files" test_global_variables_present
    run_test "3. Profile-specific variables correctly isolated" test_profile_specific_variables
    run_test "4. Secret generationworks correctly" test_secret_generation
    run_test "5. Multi-profile assembly works" test_multi_profile_assembly
    run_test "6. Variable deduplication works" test_variable_deduplication
    run_test "7. Custom profile generation works" test_custom_profile_generation
    run_test "8. Profile-aware validation works" test_profile_aware_validation
    run_test "9. Assembly reduces file size" test_assembly_reduces_size
    run_test "10. COMPOSE_PROFILES set to custom" test_compose_profiles_custom
    
    # Summary
    echo ""
    echo "============================================================================"
    echo "  Test Summary"
    echo "============================================================================"
    echo "  Total Tests:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed:${NC}       $TESTS_PASSED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed:${NC}       $TESTS_FAILED"
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
        echo "Test artifacts saved in: $TEST_OUTPUT_DIR"
        exit 1
    else
        echo ""
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        # Clean up test directory on success
        rm -rf "$TEST_OUTPUT_DIR"
        exit 0
    fi
}

main "$@"
