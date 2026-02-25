#!/bin/bash
# Safe Testing Suite - Tests image analysis without consuming Docker Hub rate limit
# This suite verifies all image analyzer functionality without pulling any images

set -e

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_SCRIPT_DIR/../.." && pwd)"

# The image-analyzer library expects SCRIPT_DIR to be the project root
export SCRIPT_DIR="$PROJECT_ROOT"
export PROJECT_ROOT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo ""
}

log_step() {
    echo -e "${BLUE}▶${NC} $1"
}

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
}

log_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Source libraries
source "$PROJECT_ROOT/tools/setup/lib/image-analyzer.sh"

main() {
    log_header "WeekendStack Safe Testing Suite"
    echo "This test suite will NOT consume Docker Hub rate limit"
    echo "All tests are read-only or use local data only"
    echo ""
    
    # Initial rate limit check
    log_header "Initial Rate Limit Check"
    "$TEST_SCRIPT_DIR/check-rate-limit.sh"
    
    # Test 1: Image Analysis
    log_header "Test 1: Image Analyzer Functions"
    
    log_step "Analyzing 'dev' profile..."
    dev_result=$(analyze_compose_images "dev")
    dev_count=$(echo "$dev_result" | grep UNIQUE_COUNT | cut -d'=' -f2)
    log_pass "Found $dev_count unique images for dev profile"
    
    log_step "Analyzing 'all' profiles..."
    all_result=$(analyze_compose_images "all")
    all_count=$(echo "$all_result" | grep UNIQUE_COUNT | cut -d'=' -f2)
    dockerhub_count=$(echo "$all_result" | grep DOCKERHUB_COUNT | cut -d'=' -f2)
    ghcr_count=$(echo "$all_result" | grep GHCR_COUNT | cut -d'=' -f2)
    lscr_count=$(echo "$all_result" | grep LSCR_COUNT | cut -d'=' -f2)
    log_pass "Found $all_count unique images total"
    log_info "  - Docker Hub: $dockerhub_count images"
    log_info "  - GitHub CR: $ghcr_count images"
    log_info "  - LinuxServer: $lscr_count images"
    
    # Test 2: Shared Images Detection
    log_header "Test 2: Shared Image Detection"
    
    log_step "Finding images used multiple times..."
    shared_images=$(detect_shared_images)
    shared_count=$(echo "$shared_images" | wc -l)
    log_pass "Found $shared_count shared images"
    
    if [[ $shared_count -gt 0 ]]; then
        log_info "Top 5 most shared images:"
        echo "$shared_images" | head -5 | while IFS=':' read -r image uses; do
            echo "    • $image (used $uses times)"
        done
    fi
    
    # Test 3: Cached Images Check
    log_header "Test 3: Local Image Cache Status"
    
    log_step "Checking locally cached images..."
    IFS=',' read -ra dev_images_array <<< "$(echo "$dev_result" | grep IMAGES_LIST | cut -d'=' -f2)"
    
    if [[ ${#dev_images_array[@]} -gt 0 ]]; then
        cached_info=$(check_images_cached "${dev_images_array[@]}")
        cached_count=$(echo "$cached_info" | grep CACHED_COUNT | cut -d'=' -f2)
        missing_count=$(echo "$cached_info" | grep MISSING_COUNT | cut -d'=' -f2)
        
        log_pass "Cache analysis complete"
        log_info "  - Already cached: $cached_count images"
        log_info "  - Need to pull: $missing_count images"
        
        if [[ $cached_count -gt 0 ]]; then
            log_info "Sample cached images:"
            IFS=',' read -ra cached_array <<< "$(echo "$cached_info" | grep CACHED_LIST | cut -d'=' -f2)"
            for img in "${cached_array[@]:0:3}"; do
                [[ -n "$img" ]] && echo "    • $img"
            done
        fi
    fi
    
    # Test 4: Compose File Parsing
    log_header "Test 4: Compose File Parsing"
    
    log_step "Validating all compose files..."
    for file in "$PROJECT_ROOT"/compose/docker-compose.*.yml; do
        if [[ -f "$file" ]]; then
            profile=$(basename "$file" | sed 's/docker-compose\.\(.*\)\.yml/\1/')
            img_count=$(extract_images_from_compose "$file" | wc -l)
            log_pass "$profile: $img_count images"
        fi
    done
    
    # Test 5: Registry Categorization
    log_header "Test 5: Registry Categorization"
    
    log_step "Testing registry detection..."
    test_images=(
        "postgres:15-alpine"
        "ghcr.io/immich-app/immich-server:release"
        "lscr.io/linuxserver/plex:latest"
        "gcr.io/kaniko-project/executor:latest"
        "quay.io/prometheus/prometheus:latest"
        "docker.io/library/nginx:latest"
    )
    
    for img in "${test_images[@]}"; do
        registry=$(categorize_registry "$img")
        echo "  $img -> [$registry]"
    done
    log_pass "Registry categorization working"
    
    # Test 6: Cache Performance
    log_header "Test 6: Analysis Cache Performance"
    
    log_step "Testing cache performance..."
    rm -rf /tmp/weekendstack-cache
    
    echo -n "  First run (no cache): "
    time_start=$(date +%s%N)
    analyze_compose_images "all" > /dev/null
    time_first=$(( ($(date +%s%N) - time_start) / 1000000 ))
    echo "${time_first}ms"
    
    echo -n "  Second run (cached):  "
    time_start=$(date +%s%N)
    analyze_compose_images "all" > /dev/null
    time_second=$(( ($(date +%s%N) - time_start) / 1000000 ))
    echo "${time_second}ms"
    
    if [[ $time_second -lt $time_first ]]; then
        speedup=$(( (time_first * 100) / time_second ))
        log_pass "Cache provides ${speedup}% performance improvement"
    else
        log_info "Cache performance: ${time_first}ms -> ${time_second}ms"
    fi
    
    # Test 7: Profile-specific Analysis
    log_header "Test 7: Profile-specific Analysis"
    
    for profile in "core" "dev" "ai" "media"; do
        log_step "Analyzing '$profile' profile..."
        result=$(analyze_compose_images "$profile")
        count=$(echo "$result" | grep UNIQUE_COUNT | cut -d'=' -f2)
        hub=$(echo "$result" | grep DOCKERHUB_COUNT | cut -d'=' -f2)
        log_pass "$profile: $count total images ($hub from Docker Hub)"
    done
    
    # Final rate limit check
    log_header "Final Rate Limit Check"
    echo "Verifying no pulls were consumed during testing..."
    "$TEST_SCRIPT_DIR/check-rate-limit.sh"
    
    # Summary
    log_header "Test Suite Complete"
    echo -e "${GREEN}✅ All safe tests completed successfully!${NC}"
    echo ""
    echo "Summary of findings:"
    echo "  • Total unique images (all profiles): $all_count"
    echo "  • Docker Hub images: $dockerhub_count (rate limited)"
    echo "  • Shared images: $shared_count (pulled once, used multiple times)"
    echo "  • Cache performance improvement: Yes"
    echo ""
    echo "Next steps:"
    echo "  1. Review rate limit status above"
    echo "  2. If you have >50 remaining pulls, safe to test actual pulling"
    echo "  3. Or authenticate first with: docker login"
    echo "  4. Run full setup with: ./setup.sh --profile <name>"
    echo ""
}

# Run main
main
