#!/bin/bash
# Test helper functions for WeekendStack test suite

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="/tmp/weekendstack-test-$$"
TEST_ENV="$TEST_DIR/test.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SUITE_NAME=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_suite_start() {
    SUITE_NAME="$1"
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    echo ""
    echo "────────────────────────────────────"
    echo "  $SUITE_NAME"
    echo "────────────────────────────────────"
}

test_suite_end() {
    echo ""
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $SUITE_NAME: All $TESTS_PASSED tests passed"
    else
        echo -e "${RED}✗${NC} $SUITE_NAME: $TESTS_FAILED/$TESTS_RUN tests failed"
        exit 1
    fi
}

test_case() {
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST="$1"
    echo -n "  $1... "
}

test_pass() {
    echo -e "${GREEN}✓${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo -e "${RED}✗${NC}"
    echo "    Error: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_skip() {
    echo -e "${YELLOW}○${NC} (skipped: $1)"
}

create_temp_env() {
    mkdir -p "$TEST_DIR"
    touch "$TEST_ENV"
}

cleanup_temp() {
    rm -rf "$TEST_DIR"
}

backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.test-backup"
    fi
}

restore_file() {
    if [ -f "$1.test-backup" ]; then
        mv "$1.test-backup" "$1"
    else
        rm -f "$1"
    fi
}

# Load the update_env_var function for testing
update_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env_file="$3"
    
    awk -v var="$var_name" -v val="$var_value" '
        $0 ~ "^" var "=" { print var "=" val; next }
        { print }
    ' "$env_file" > "${env_file}.tmp" && mv "${env_file}.tmp" "$env_file"
}

# Cleanup on exit
trap cleanup_temp EXIT
