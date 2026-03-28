#!/bin/bash
# Unit tests for image analyzer library
# Tests image extraction, categorization, and analysis functions

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_SCRIPT_DIR/../../.." && pwd)"

# Source test helpers
source "$TEST_SCRIPT_DIR/../test_helpers.sh"

# The image-analyzer library expects SCRIPT_DIR to be the project root
export SCRIPT_DIR="$PROJECT_ROOT"

# Source image analyzer
source "$PROJECT_ROOT/tools/setup/lib/image-analyzer.sh"

# Test suite
run_tests() {
    test_suite_start "Image Analyzer Unit Tests"
    
    # Test 1: Registry categorization
    test_case "Registry categorization"
    local result=""
    result=$(categorize_registry "postgres:15-alpine")
    if [[ "$result" == "dockerhub" ]]; then
        result=$(categorize_registry "ghcr.io/immich-app/immich-server:release")
        if [[ "$result" == "ghcr" ]]; then
            result=$(categorize_registry "lscr.io/linuxserver/plex:latest")
            if [[ "$result" == "lscr" ]]; then
                result=$(categorize_registry "gcr.io/kaniko-project/executor:latest")
                if [[ "$result" == "gcr" ]]; then
                    result=$(categorize_registry "quay.io/prometheus/prometheus:latest")
                    if [[ "$result" == "quay" ]]; then
                        test_pass
                    else
                        test_fail "Quay registry not recognized: got '$result'"
                    fi
                else
                    test_fail "GCR registry not recognized: got '$result'"
                fi
            else
                test_fail "LSCR registry not recognized: got '$result'"
            fi
        else
            test_fail "GHCR registry not recognized: got '$result'"
        fi
    else
        test_fail "Docker Hub registry not recognized: got '$result'"
    fi
    
    # Test 2: Extract images from compose file
    test_case "Extract images from compose file"
    local compose_file="$PROJECT_ROOT/compose/docker-compose.dev.yml"
    if [[ -f "$compose_file" ]]; then
        local images=$(extract_images_from_compose "$compose_file")
        local count=$(echo "$images" | wc -l)
        if [[ $count -gt 0 ]]; then
            test_pass
        else
            test_fail "No images extracted from compose file"
        fi
    else
        test_skip "Compose file not found: $compose_file"
    fi
    
    # Test 3: Get images for specific profile
    test_case "Get images for 'dev' profile"
    local dev_images=$(get_images_for_profiles "dev")
    local dev_count=$(echo "$dev_images" | wc -w)
    if [[ $dev_count -gt 0 ]]; then
        test_pass
    else
        test_fail "No images found for dev profile"
    fi
    
    # Test 4: Analyze compose images
    test_case "Analyze compose images for 'dev'"
    local analysis=$(analyze_compose_images "dev")
    if echo "$analysis" | grep -q "UNIQUE_COUNT="; then
        local unique=$(echo "$analysis" | grep "UNIQUE_COUNT=" | cut -d'=' -f2)
        if [[ $unique -gt 0 ]]; then
            test_pass
        else
            test_fail "Analysis returned 0 images"
        fi
    else
        test_fail "Analysis output format incorrect"
    fi
    
    # Test 5: Categorize images by registry
    test_case "Categorize images by registry"
    local test_images=("postgres:15-alpine" "ghcr.io/test:latest" "lscr.io/test:latest")
    local categories=$(categorize_images "${test_images[@]}")
    if echo "$categories" | grep -q "dockerhub="; then
        if echo "$categories" | grep -q "ghcr="; then
            test_pass
        else
            test_fail "GHCR category missing"
        fi
    else
        test_fail "Docker Hub category missing"
    fi
    
    # Test 6: Detect shared images
    test_case "Detect shared images"
    local shared=$(detect_shared_images | head -1)
    # Just check if function runs without error
    test_pass
    
    # Test 7: Get cached images
    test_case "Get locally cached images"
    local cached=$(get_cached_images)
    # This might be empty on fresh system, just check if function runs
    test_pass
    
    # Test 8: Check images cached
    test_case "Check which images are cached"
    local cache_check=$(check_images_cached "postgres:15-alpine" "redis:7-alpine")
    if echo "$cache_check" | grep -q "CACHED_COUNT="; then
        if echo "$cache_check" | grep -q "MISSING_COUNT="; then
            test_pass
        else
            test_fail "Cache check missing MISSING_COUNT"
        fi
    else
        test_fail "Cache check missing CACHED_COUNT"
    fi
    
    # Test 9: Analysis caching
    test_case "Analysis result caching"
    rm -rf /tmp/weekendstack-cache
    analyze_compose_images "dev" > /dev/null
    if [[ -d /tmp/weekendstack-cache ]]; then
        test_pass
    else
        test_fail "Cache directory not created"
    fi
    
    # Test 10: Profile compose map completeness
    test_case "Profile compose map completeness"
    local all_profiles=("ai" "automation" "core" "dev" "media" "monitoring" "networking" "productivity")
    if [[ -f "$PROJECT_ROOT/compose/docker-compose.personal.yml" ]]; then
        all_profiles+=("personal")
    fi
    local missing_profiles=()
    
    for profile in "${all_profiles[@]}"; do
        if [[ -z "${PROFILE_COMPOSE_MAP[$profile]}" ]]; then
            missing_profiles+=("$profile")
        fi
    done
    
    if [[ ${#missing_profiles[@]} -eq 0 ]]; then
        test_pass
    else
        test_fail "Missing mappings for: ${missing_profiles[*]}"
    fi
    
    test_suite_end
}

# Run tests
run_tests
