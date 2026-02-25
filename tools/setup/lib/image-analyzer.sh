#!/bin/bash
# Image analysis and manifest generation for WeekendStack
# Parses Docker Compose files to extract image information

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Determine project root directory
# Can be set by calling script or auto-detected
if [[ -z "$SCRIPT_DIR" ]]; then
    # Find project root by looking for docker-compose.yml
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

# Cache file for parsed image data
CACHE_DIR="/tmp/weekendstack-cache"
mkdir -p "$CACHE_DIR"

# Mapping of profiles to compose files
declare -A PROFILE_COMPOSE_MAP=(
    ["ai"]="compose/docker-compose.ai.yml"
    ["automation"]="compose/docker-compose.automation.yml"
    ["core"]="compose/docker-compose.core.yml"
    ["dev"]="compose/docker-compose.dev.yml"
    ["media"]="compose/docker-compose.media.yml"
    ["monitoring"]="compose/docker-compose.monitoring.yml"
    ["networking"]="compose/docker-compose.networking.yml"
    ["personal"]="compose/docker-compose.personal.yml"
    ["productivity"]="compose/docker-compose.productivity.yml"
)

# Registry patterns for categorization
categorize_registry() {
    local image="$1"
    
    case "$image" in
        ghcr.io/*)
            echo "ghcr"
            ;;
        lscr.io/*)
            echo "lscr"
            ;;
        gcr.io/*)
            echo "gcr"
            ;;
        quay.io/*)
            echo "quay"
            ;;
        docker.io/*|docker.n8n.io/*)
            echo "dockerhub"
            ;;
        registry:*|postgres:*|redis:*|mongo:*|alpine:*|nginx:*|mariadb:*|traefik:*)
            # Official images without explicit registry
            echo "dockerhub"
            ;;
        */*)
            # Has slash but no registry domain - Docker Hub user images
            echo "dockerhub"
            ;;
        *)
            echo "dockerhub"
            ;;
    esac
}

# Extract images from a compose file
extract_images_from_compose() {
    local compose_file="$1"
    
    if [[ ! -f "$compose_file" ]]; then
        return 1
    fi
    
    # Extract image: lines, handle variable substitution
    grep -E "^\s+image:\s+" "$compose_file" | \
        sed 's/^\s*image:\s*//' | \
        sed 's/\s*#.*$//' | \
        sed 's/"//g' | \
        sed "s/\${IMMICH_VERSION:-release}/release/g" | \
        sed "s/\${HOARDER_VERSION:-release}/release/g" | \
        sed "s/\${CONFIG_BASE_DIR:-.\/config}/.\/config/g" | \
        sort -u
}

# Extract build contexts (services that build custom images)
extract_builds_from_compose() {
    local compose_file="$1"
    
    if [[ ! -f "$compose_file" ]]; then
        return 1
    fi
    
    # Extract build: context lines
    grep -E "^\s+(build:|context:)\s+" "$compose_file" | \
        sed 's/^\s*context:\s*//' | \
        sed 's/^\s*build:\s*//' | \
        sed 's/\s*#.*$//' | \
        sed 's/"//g' | \
        grep -v "^build:" | \
        sort -u
}

# Get all images for selected profiles
get_images_for_profiles() {
    local profiles=("$@")
    local -a all_images=()
    local -a compose_files=()
    
    # If 'all' is in profiles, use all compose files
    if [[ " ${profiles[*]} " =~ " all " ]]; then
        compose_files=(
            "compose/docker-compose.ai.yml"
            "compose/docker-compose.automation.yml"
            "compose/docker-compose.core.yml"
            "compose/docker-compose.dev.yml"
            "compose/docker-compose.media.yml"
            "compose/docker-compose.monitoring.yml"
            "compose/docker-compose.networking.yml"
            "compose/docker-compose.personal.yml"
            "compose/docker-compose.productivity.yml"
        )
    else
        # Map profiles to compose files
        for profile in "${profiles[@]}"; do
            if [[ -n "${PROFILE_COMPOSE_MAP[$profile]}" ]]; then
                compose_files+=("${PROFILE_COMPOSE_MAP[$profile]}")
            fi
        done
    fi
    
    # Extract images from all selected compose files
    for compose_file in "${compose_files[@]}"; do
        local full_path="$SCRIPT_DIR/$compose_file"
        if [[ -f "$full_path" ]]; then
            while IFS= read -r image; do
                [[ -n "$image" ]] && all_images+=("$image")
            done < <(extract_images_from_compose "$full_path")
        fi
    done
    
    # Remove duplicates and sort
    printf '%s\n' "${all_images[@]}" | sort -u
}

# Count images by registry
categorize_images() {
    local -a images=("$@")
    
    declare -A registry_counts=(
        ["dockerhub"]=0
        ["ghcr"]=0
        ["lscr"]=0
        ["gcr"]=0
        ["quay"]=0
        ["other"]=0
    )
    
    for image in "${images[@]}"; do
        local registry=$(categorize_registry "$image")
        ((registry_counts[$registry]++))
    done
    
    # Output as key=value pairs
    for registry in "${!registry_counts[@]}"; do
        echo "$registry=${registry_counts[$registry]}"
    done
}

# Detect shared/duplicate images across compose files
detect_shared_images() {
    local -a images=("$@")
    
    declare -A image_count
    
    # Count occurrences across all compose files
    for compose_file in compose/docker-compose.*.yml; do
        while IFS= read -r image; do
            [[ -n "$image" ]] && ((image_count[$image]++))
        done < <(extract_images_from_compose "$compose_file")
    done
    
    # Output images used more than once
    for image in "${!image_count[@]}"; do
        if [[ ${image_count[$image]} -gt 1 ]]; then
            echo "$image:${image_count[$image]}"
        fi
    done | sort -t: -k2 -rn
}

# Get comprehensive analysis for profiles
analyze_compose_images() {
    local profiles=("$@")
    
    # Generate cache key from profiles
    local profile_str="${profiles[*]}"
    local cache_key=$(echo -n "$profile_str" | md5sum | cut -d' ' -f1)
    local cache_file="$CACHE_DIR/images-${cache_key}.cache"
    
    # Return cached data if available and recent (< 5 minutes old)
    if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(stat -c %Y "$cache_file"))) -lt 300 ]]; then
        cat "$cache_file"
        return 0
    fi
    
    # Get unique images for selected profiles
    local -a images=()
    while IFS= read -r image; do
        [[ -n "$image" ]] && images+=("$image")
    done < <(get_images_for_profiles "${profiles[@]}")
    
    local unique_count=${#images[@]}
    
    # Categorize by registry
    declare -A registry_counts
    while IFS='=' read -r registry count; do
        registry_counts[$registry]=$count
    done < <(categorize_images "${images[@]}")
    
    # Get shared images
    local -a shared_images=()
    while IFS= read -r shared; do
        [[ -n "$shared" ]] && shared_images+=("$shared")
    done < <(detect_shared_images "${images[@]}")
    
    # Build JSON-like output (simple key=value format for shell parsing)
    local output=""
    output+="UNIQUE_COUNT=$unique_count"$'\n'
    output+="DOCKERHUB_COUNT=${registry_counts[dockerhub]:-0}"$'\n'
    output+="GHCR_COUNT=${registry_counts[ghcr]:-0}"$'\n'
    output+="LSCR_COUNT=${registry_counts[lscr]:-0}"$'\n'
    output+="GCR_COUNT=${registry_counts[gcr]:-0}"$'\n'
    output+="QUAY_COUNT=${registry_counts[quay]:-0}"$'\n'
    output+="OTHER_COUNT=${registry_counts[other]:-0}"$'\n'
    output+="SHARED_COUNT=${#shared_images[@]}"$'\n'
    output+="IMAGES_LIST=$(printf '%s,' "${images[@]}" | sed 's/,$//')"$'\n'
    output+="SHARED_LIST=$(printf '%s,' "${shared_images[@]}" | sed 's/,$//')"$'\n'
    
    # Ensure cache directory exists before writing
    mkdir -p "$(dirname "$cache_file")" 2>/dev/null || true
    
    # Cache the result
    echo "$output" > "$cache_file"
    echo "$output"
}

# Get images already available locally
get_cached_images() {
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>"
}

# Check which images from list are already pulled
check_images_cached() {
    local -a needed_images=("$@")
    local -a cached=()
    local -a missing=()
    
    # Get local images
    local -a local_images=()
    while IFS= read -r img; do
        local_images+=("$img")
    done < <(get_cached_images)
    
    # Check each needed image
    for needed in "${needed_images[@]}"; do
        if printf '%s\n' "${local_images[@]}" | grep -qF "$needed"; then
            cached+=("$needed")
        else
            missing+=("$needed")
        fi
    done
    
    echo "CACHED_COUNT=${#cached[@]}"
    echo "MISSING_COUNT=${#missing[@]}"
    echo "CACHED_LIST=$(printf '%s,' "${cached[@]}" | sed 's/,$//')"
    echo "MISSING_LIST=$(printf '%s,' "${missing[@]}" | sed 's/,$//')"
}

# Export functions for use in other scripts
export -f categorize_registry
export -f extract_images_from_compose
export -f get_images_for_profiles
export -f categorize_images
export -f detect_shared_images
export -f analyze_compose_images
export -f get_cached_images
export -f check_images_cached
