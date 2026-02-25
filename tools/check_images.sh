#!/bin/bash
# Check Docker images required for WeekendStack profiles
# Usage: ./tools/check_images.sh [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR

# Load libraries
source "$SCRIPT_DIR/tools/setup/lib/common.sh"
source "$SCRIPT_DIR/tools/setup/lib/image-analyzer.sh"
source "$SCRIPT_DIR/tools/setup/lib/docker-auth.sh"

# Default options
PROFILE="all"
SHOW_CACHED=false
ESTIMATE_SIZE=false
CHECK_LIMITS=false
OUTPUT_FORMAT="table"

# Show usage
show_usage() {
    cat << EOF
WeekendStack Image Checker

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --profile <name>        Profile to check (default: all)
                           Options: all, core, networking, dev, ai, media,
                                   monitoring, productivity, personal, automation
    --show-cached          Show which images are already pulled locally
    --estimate-size        Query registries for image sizes (slower)
    --check-limits         Display Docker Hub rate limit status
    --format <type>        Output format: table (default), json, summary
    -h, --help             Show this help message

EXAMPLES:
    # Check images for all profiles
    $0 --profile all

    # Check dev profile with cached images info
    $0 --profile dev --show-cached

    # Get JSON output for automation
    $0 --profile ai --format json

    # Check rate limits and required images
    $0 --profile all --check-limits

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --show-cached)
            SHOW_CACHED=true
            shift
            ;;
        --estimate-size)
            ESTIMATE_SIZE=true
            shift
            ;;
        --check-limits)
            CHECK_LIMITS=true
            shift
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main analysis
main() {
    log_header "WeekendStack Image Analysis"
    
    echo "Analyzing images for profile: $PROFILE"
    echo ""
    
    # Get image analysis
    local analysis=$(analyze_compose_images "$PROFILE")
    
    # Parse analysis data
    declare -A data
    while IFS='=' read -r key value; do
        data[$key]="$value"
    done <<< "$analysis"
    
    local unique_count="${data[UNIQUE_COUNT]:-0}"
    local dockerhub_count="${data[DOCKERHUB_COUNT]:-0}"
    local ghcr_count="${data[GHCR_COUNT]:-0}"
    local lscr_count="${data[LSCR_COUNT]:-0}"
    local gcr_count="${data[GCR_COUNT]:-0}"
    local quay_count="${data[QUAY_COUNT]:-0}"
    local other_count="${data[OTHER_COUNT]:-0}"
    local shared_count="${data[SHARED_COUNT]:-0}"
    
    # Get images list
    IFS=',' read -ra images_array <<< "${data[IMAGES_LIST]}"
    
    # Output based on format
    case "$OUTPUT_FORMAT" in
        json)
            output_json
            ;;
        summary)
            output_summary
            ;;
        table|*)
            output_table
            ;;
    esac
}

# Table output
output_table() {
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                     IMAGE REQUIREMENTS"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    printf "  %-30s %s\n" "Total Unique Images:" "$unique_count"
    echo ""
    echo "  Images by Registry:"
    printf "    %-28s %s\n" "Docker Hub (rate limited):" "$dockerhub_count"
    printf "    %-28s %s\n" "GitHub Container Registry:" "$ghcr_count"
    printf "    %-28s %s\n" "LinuxServer.io:" "$lscr_count"
    
    local other_total=$((gcr_count + quay_count + other_count))
    if [[ $other_total -gt 0 ]]; then
        printf "    %-28s %s\n" "Other registries:" "$other_total"
    fi
    
    if [[ $shared_count -gt 0 ]]; then
        echo ""
        echo "  Shared Images (used multiple times):"
        printf "    %-28s %s\n" "Count:" "$shared_count"
        echo "    These will only be pulled once"
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    
    # Show cached status if requested
    if $SHOW_CACHED; then
        echo ""
        log_step "Checking locally cached images..."
        
        local cache_info=$(check_images_cached "${images_array[@]}")
        
        declare -A cache_data
        while IFS='=' read -r key value; do
            cache_data[$key]="$value"
        done <<< "$cache_info"
        
        local cached_count="${cache_data[CACHED_COUNT]:-0}"
        local missing_count="${cache_data[MISSING_COUNT]:-0}"
        
        echo ""
        echo "  Locally Cached Images: $cached_count"
        echo "  Images to Pull: $missing_count"
        
        if [[ $cached_count -gt 0 ]] && [[ "$OUTPUT_FORMAT" == "table" ]]; then
            echo ""
            echo "  Already pulled (will be skipped):"
            IFS=',' read -ra cached_array <<< "${cache_data[CACHED_LIST]}"
            for img in "${cached_array[@]:0:10}"; do
                [[ -n "$img" ]] && echo "    • $img"
            done
            if [[ ${#cached_array[@]} -gt 10 ]]; then
                echo "    ... and $((${#cached_array[@]} - 10)) more"
            fi
        fi
    fi
    
    # Show rate limit status if requested
    if $CHECK_LIMITS; then
        echo ""
        log_step "Docker Hub Rate Limit Status"
        echo ""
        format_rate_limit_status | sed 's/^/  /'
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    # Show top shared images
    if [[ -n "${data[SHARED_LIST]}" ]] && [[ "${data[SHARED_LIST]}" != "" ]]; then
        echo "Most commonly used images:"
        IFS=',' read -ra shared_array <<< "${data[SHARED_LIST]}"
        local count=0
        for shared in "${shared_array[@]}"; do
            if [[ $count -lt 5 ]] && [[ -n "$shared" ]]; then
                IFS=':' read -r image uses <<< "$shared"
                echo "  • $image (used $uses times)"
                ((count++))
            fi
        done
        echo ""
    fi
    
    # Show all images in detail
    echo "Complete image list:"
    echo ""
    for image in "${images_array[@]}"; do
        if [[ -n "$image" ]]; then
            local registry=$(categorize_registry "$image")
            printf "  %-50s [%s]\n" "$image" "$registry"
        fi
    done
    echo ""
}

# Summary output
output_summary() {
    echo "Profile: $PROFILE"
    echo "Total Images: $unique_count"
    echo "Docker Hub: $dockerhub_count"
    echo "GitHub: $ghcr_count"
    echo "LinuxServer: $lscr_count"
    echo "Other: $((gcr_count + quay_count + other_count))"
    echo "Shared: $shared_count"
    
    if $SHOW_CACHED; then
        local cache_info=$(check_images_cached "${images_array[@]}")
        declare -A cache_data
        while IFS='=' read -r key value; do
            cache_data[$key]="$value"
        done <<< "$cache_info"
        echo "Cached: ${cache_data[CACHED_COUNT]:-0}"
        echo "To Pull: ${cache_data[MISSING_COUNT]:-0}"
    fi
}

# JSON output
output_json() {
    cat << EOF
{
  "profile": "$PROFILE",
  "total_unique_images": $unique_count,
  "registries": {
    "dockerhub": $dockerhub_count,
    "ghcr": $ghcr_count,
    "lscr": $lscr_count,
    "gcr": $gcr_count,
    "quay": $quay_count,
    "other": $other_count
  },
  "shared_images_count": $shared_count,
  "images": [
EOF

    local first=true
    for image in "${images_array[@]}"; do
        if [[ -n "$image" ]]; then
            [[ "$first" == "false" ]] && echo ","
            first=false
            local registry=$(categorize_registry "$image")
            echo -n "    {\"image\": \"$image\", \"registry\": \"$registry\"}"
        fi
    done
    
    echo ""
    echo "  ]"
    
    if $SHOW_CACHED; then
        local cache_info=$(check_images_cached "${images_array[@]}")
        declare -A cache_data
        while IFS='=' read -r key value; do
            cache_data[$key]="$value"
        done <<< "$cache_info"
        
        echo "  \"local_cache\": {"
        echo "    \"cached_count\": ${cache_data[CACHED_COUNT]:-0},"
        echo "    \"missing_count\": ${cache_data[MISSING_COUNT]:-0}"
        echo "  }"
    fi
    
    echo "}"
}

# Run main
main
