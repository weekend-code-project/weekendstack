#!/bin/bash
# WeekendStack Test Runner
# Runs unit, integration, and smoke tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Test result tracking
declare -a FAILED_TESTS

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo ""
}

run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    echo -e "${BLUE}▶${NC} Running: $test_name"
    
    if bash "$test_file"; then
        echo -e "${GREEN}✓${NC} $test_name completed"
        return 0
    else
        echo -e "${RED}✗${NC} $test_name failed"
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

run_unit_tests() {
    log_header "Unit Tests"
    
    local failed=0
    for test_file in "$SCRIPT_DIR/unit"/*.sh; do
        if [ -f "$test_file" ]; then
            run_test_file "$test_file" || failed=$((failed + 1))
        fi
    done
    
    return $failed
}

run_integration_tests() {
    log_header "Integration Tests"
    
    local failed=0
    for test_file in "$SCRIPT_DIR/integration"/*.sh; do
        if [ -f "$test_file" ]; then
            run_test_file "$test_file" || failed=$((failed + 1))
        fi
    done
    
    return $failed
}

run_smoke_tests() {
    log_header "Smoke Tests"
    
    local failed=0
    for test_file in "$SCRIPT_DIR/smoke"/*.sh; do
        if [ -f "$test_file" ]; then
            run_test_file "$test_file" || failed=$((failed + 1))
        fi
    done
    
    return $failed
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [CATEGORY]

Run WeekendStack test suite

CATEGORIES:
    unit          Run only unit tests
    integration   Run only integration tests
    smoke         Run only smoke tests
    all           Run all tests (default)

OPTIONS:
    -h, --help    Show this help message
    -v, --verbose Enable verbose output

EXAMPLES:
    $0                  # Run all tests
    $0 unit             # Run only unit tests
    $0 integration      # Run integration tests

EOF
}

# Parse arguments
VERBOSE=false
CATEGORY="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        unit|integration|smoke|all)
            CATEGORY="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
clear
echo ""
echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║    WeekendStack Test Suite            ║${NC}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo "Project: $PROJECT_ROOT"
echo "Test Category: $CATEGORY"
echo ""

START_TIME=$(date +%s)
FAILED_SUITES=0

case "$CATEGORY" in
    unit)
        run_unit_tests || FAILED_SUITES=$?
        ;;
    integration)
        run_integration_tests || FAILED_SUITES=$?
        ;;
    smoke)
        run_smoke_tests || FAILED_SUITES=$?
        ;;
    all)
        run_unit_tests || FAILED_SUITES=$((FAILED_SUITES + $?))
        run_integration_tests || FAILED_SUITES=$((FAILED_SUITES + $?))
        run_smoke_tests || FAILED_SUITES=$((FAILED_SUITES + $?))
        ;;
    *)
        echo "Invalid category: $CATEGORY"
        show_usage
        exit 1
        ;;
esac

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Summary
log_header "Test Results"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "${RED}Failed test suites:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗${NC} $test"
    done
    echo ""
fi

echo "Duration: ${DURATION}s"
echo ""

if [ $FAILED_SUITES -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ $FAILED_SUITES test suite(s) failed${NC}"
    echo ""
    exit 1
fi
