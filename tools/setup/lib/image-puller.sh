#!/bin/bash
# Smart image pulling orchestration
# Handles optimized multi-phase image pulling with registry cache

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/image-analyzer.sh"
source "$(dirname "${BASH_SOURCE[0]}")/registry-cache.sh"

# Pull log file
PULL_LOG="/tmp/weekendstack-pull.log"
PULL_FAILURES="/tmp/weekendstack-pull-failures.log"

# Show comprehensive pre-pull plan
show_pull_plan() {
    local analysis="$1"
    local limit_status="$2"
    
    # Parse analysis data
    declare -A data
    while IFS='=' read -r key value; do
        data[$key]="$value"
    done <<< "$analysis"
    
    local unique_count="${data[UNIQUE_COUNT]:-0}"
    local dockerhub_count="${data[DOCKERHUB_COUNT]:-0}"
    local ghcr_count="${data[GHCR_COUNT]:-0}"
    local lscr_count="${data[LSCR_COUNT]:-0}"
    local shared_count="${data[SHARED_COUNT]:-0}"
    
    clear
    log_header "Image Pull Plan"

    local other_count=$(( ${data[GCR_COUNT]:-0} + ${data[QUAY_COUNT]:-0} + ${data[OTHER_COUNT]:-0} ))

    log_info "Total images to pull: $unique_count"
    echo ""
    echo "  By registry:"
    echo "  • Docker Hub (rate limited):   $dockerhub_count images"
    echo "  • GitHub Container Registry:   $ghcr_count images"
    echo "  • LinuxServer.io:              $lscr_count images"
    echo "  • Other registries:            $other_count images"
    echo ""

    if [[ $shared_count -gt 0 ]]; then
        log_info "$shared_count shared images (postgres, redis, alpine) will only be pulled once"
        echo ""
    fi
    
    if [[ "$SETUP_MODE" == "interactive" ]]; then
        echo "This process may take several minutes depending on your connection."
        echo ""
        # Make read non-fatal in case stdin is unavailable
        read -p "Press Enter to begin pulling images..." -r || {
            echo "(Continuing automatically - stdin unavailable)"
            sleep 2
        }
        clear
    fi
}

# Pull a single image with retry logic
pull_single_image() {
    local image="$1"
    local max_retries=3
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if docker pull "$image" 2>&1 | tee -a "$PULL_LOG"; then
            return 0
        fi
        
        ((retry++))
        if [[ $retry -lt $max_retries ]]; then
            log_warn "Retry $retry/$max_retries for $image"
            sleep 2
        fi
    done
    
    echo "$image" >> "$PULL_FAILURES"
    return 1
}

# Pull images in a specific phase
pull_phase() {
    local phase_name="$1"
    shift
    local -a images=("$@")
    
    if [[ ${#images[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_step "$phase_name (${#images[@]} images)"
    echo ""
    
    local pulled=0
    local failed=0
    
    for image in "${images[@]}"; do
        echo -n "  Pulling: $image ... "
        
        if pull_single_image "$image" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            ((pulled++))
        else
            echo -e "${RED}✗${NC}"
            ((failed++))
        fi
    done
    
    echo ""
    if [[ $failed -eq 0 ]]; then
        log_success "Phase complete: $pulled images pulled successfully"
    else
        log_warn "Phase complete: $pulled succeeded, $failed failed"
    fi
    echo ""
    
    return 0
}

# Categorize images into pull phases
categorize_pull_phases() {
    local -a all_images=("$@")
    
    local -a phase1_shared=()
    local -a phase2_nonhub=()
    local -a phase3_hub=()
    
    for image in "${all_images[@]}"; do
        # Phase 1: Shared base images (postgres, redis, alpine)
        if [[ "$image" =~ ^postgres: ]] || \
           [[ "$image" =~ ^redis: ]] || \
           [[ "$image" =~ ^alpine: ]] || \
           [[ "$image" =~ ^mongo: ]]; then
            phase1_shared+=("$image")
        # Phase 2: Non-Docker-Hub registries
        elif [[ "$image" =~ ^ghcr\.io/ ]] || \
             [[ "$image" =~ ^lscr\.io/ ]] || \
             [[ "$image" =~ ^gcr\.io/ ]] || \
             [[ "$image" =~ ^quay\.io/ ]]; then
            phase2_nonhub+=("$image")
        # Phase 3: Docker Hub images
        else
            phase3_hub+=("$image")
        fi
    done
    
    # Output as delimited lists
    echo "PHASE1=$(printf '%s,' "${phase1_shared[@]}" | sed 's/,$//')"
    echo "PHASE2=$(printf '%s,' "${phase2_nonhub[@]}" | sed 's/,$//')"
    echo "PHASE3=$(printf '%s,' "${phase3_hub[@]}" | sed 's/,$//')"
}

# Optimized image pulling with phases
pull_images_optimized() {
    local profiles=("$@")
    
    log_header "Pulling Docker Images"
    
    # Initialize log files
    > "$PULL_LOG"
    > "$PULL_FAILURES"
    
    echo "Starting optimized image pull for profiles: ${profiles[*]}"
    echo "Detailed log: $PULL_LOG"
    echo ""
    
    # Get image analysis
    log_step "Analyzing required images..."
    local analysis=$(analyze_compose_images "${profiles[@]}")
    
    declare -A data
    while IFS='=' read -r key value; do
        data[$key]="$value"
    done <<< "$analysis"
    
    # Extract image list
    local images_list="${data[IMAGES_LIST]}"
    IFS=',' read -ra all_images <<< "$images_list"
    
    if [[ ${#all_images[@]} -eq 0 ]]; then
        log_error "No images found for selected profiles"
        return 1
    fi
    
    log_success "Found ${#all_images[@]} unique images to pull"
    echo ""
    
    # Phase 0: Start registry cache
    log_header "Phase 0: Registry Cache Setup"
    if ! start_registry_cache; then
        log_warn "Registry cache failed to start, continuing with direct pulls"
        log_warn "This may result in rate limiting from Docker Hub"
        echo ""
        
        if [[ "$SETUP_MODE" == "interactive" ]]; then
            if ! prompt_yes_no "Continue without cache?" "y"; then
                return 1
            fi
        fi
    fi
    echo ""
    
    # Categorize images into phases
    local phase_data=$(categorize_pull_phases "${all_images[@]}")
    
    declare -A phases
    while IFS='=' read -r key value; do
        phases[$key]="$value"
    done <<< "$phase_data"
    
    # Convert phase data back to arrays
    IFS=',' read -ra phase1_images <<< "${phases[PHASE1]}"
    IFS=',' read -ra phase2_images <<< "${phases[PHASE2]}"
    IFS=',' read -ra phase3_images <<< "${phases[PHASE3]}"
    
    # Execute phases
    log_header "Phase 1: Shared Base Images"
    if [[ ${#phase1_images[@]} -gt 0 ]]; then
        pull_phase "Pulling shared images (postgres, redis, alpine)" "${phase1_images[@]}"
    else
        log_info "No shared base images needed"
        echo ""
    fi
    
    log_header "Phase 2: Non-Docker-Hub Images"
    if [[ ${#phase2_images[@]} -gt 0 ]]; then
        pull_phase "Pulling from GitHub, LinuxServer.io, and other registries" "${phase2_images[@]}"
    else
        log_info "No non-Docker-Hub images needed"
        echo ""
    fi
    
    log_header "Phase 3: Docker Hub Images"
    if [[ ${#phase3_images[@]} -gt 0 ]]; then
        pull_phase "Pulling Docker Hub images via cache" "${phase3_images[@]}"
    else
        log_info "No Docker Hub images needed"
        echo ""
    fi
    
    # Summary
    log_header "Pull Summary"
    
    local total_pulled=$((${#all_images[@]}))
    local failed_count=0
    
    if [[ -f "$PULL_FAILURES" ]]; then
        failed_count=$(wc -l < "$PULL_FAILURES")
    fi
    
    local success_count=$((total_pulled - failed_count))
    
    echo "Total images: $total_pulled"
    echo "Successfully pulled: $success_count"
    echo "Failed: $failed_count"
    echo ""
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Some images failed to pull. See: $PULL_FAILURES"
        echo ""
        echo "Failed images:"
        cat "$PULL_FAILURES"
        echo ""
        
        if [[ "$SETUP_MODE" == "interactive" ]]; then
            if ! prompt_yes_no "Continue anyway?" "y"; then
                return 1
            fi
        fi
    else
        log_success "All images pulled successfully!"
    fi
    
    # Show cache stats if running
    if is_cache_running; then
        echo ""
        log_step "Registry cache statistics:"
        get_cache_stats | sed 's/^/  /'
        echo ""
    fi
    
    return 0
}

# Export functions
export -f show_pull_plan
export -f pull_single_image
export -f pull_phase
export -f categorize_pull_phases
export -f pull_images_optimized
