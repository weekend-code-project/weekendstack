#!/bin/bash
# Post-install disk cleanup helpers

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

human_size_to_bytes() {
    local size="$1"

    if [[ -z "$size" || "$size" == "0" || "$size" == "0B" ]]; then
        echo "0"
        return 0
    fi

    awk -v size="$size" '
        BEGIN {
            if (match(size, /^([0-9.]+)([A-Za-z]+)$/, parts) == 0) {
                print 0
                exit
            }

            value = parts[1] + 0
            unit = parts[2]

            multiplier["B"] = 1
            multiplier["kB"] = 1000
            multiplier["MB"] = 1000 * 1000
            multiplier["GB"] = 1000 * 1000 * 1000
            multiplier["TB"] = 1000 * 1000 * 1000 * 1000

            if (!(unit in multiplier)) {
                print 0
                exit
            }

            printf "%.0f\n", value * multiplier[unit]
        }
    '
}

bytes_to_human() {
    local bytes="${1:-0}"

    awk -v bytes="$bytes" '
        BEGIN {
            split("B kB MB GB TB", unit, " ")
            idx = 1

            while (bytes >= 1000 && idx < 5) {
                bytes /= 1000
                idx++
            }

            if (idx == 1 || bytes >= 10) {
                printf "%.0f%s\n", bytes, unit[idx]
            } else {
                printf "%.1f%s\n", bytes, unit[idx]
            }
        }
    '
}

docker_df_image_field_from_text() {
    local report="$1"
    local field="$2"

    awk -v field="$field" '
        $1 == "Images" {
            if (field == "size") {
                print $4
            } else if (field == "reclaimable") {
                print $5
            } else if (field == "active") {
                print $3
            } else if (field == "total") {
                print $2
            }
            exit
        }
    ' <<< "$report"
}

get_root_disk_usage_percent() {
    df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}

get_root_disk_usage_summary() {
    df -h / 2>/dev/null | awk 'NR == 2 { printf "%s / %s used (%s)", $3, $2, $5 }'
}

get_docker_image_total_human() {
    local report
    report=$(docker system df 2>/dev/null || true)
    docker_df_image_field_from_text "$report" "size"
}

get_docker_image_reclaimable_human() {
    local report
    report=$(docker system df 2>/dev/null || true)
    docker_df_image_field_from_text "$report" "reclaimable"
}

should_offer_post_install_cleanup() {
    local disk_usage="${1:-$(get_root_disk_usage_percent)}"
    local reclaimable_human="${2:-$(get_docker_image_reclaimable_human)}"
    local reclaimable_bytes

    reclaimable_bytes=$(human_size_to_bytes "$reclaimable_human")

    if [[ -z "$disk_usage" ]]; then
        disk_usage=0
    fi

    (( disk_usage >= 80 || reclaimable_bytes >= 1000000000 ))
}

run_post_install_cleanup() {
    local free_before free_after reclaimable

    free_before=$(df -h / 2>/dev/null | awk 'NR == 2 { print $4 }')
    reclaimable=$(get_docker_image_reclaimable_human)

    log_header "Reclaiming Disk Space"
    log_info "Removing unused Docker images and local package caches"

    echo ""
    log_step "Pruning unused Docker images..."
    docker image prune -af 2>&1 | grep -E 'Total reclaimed|^deleted:' | tail -5 || true

    echo ""
    log_step "Pruning Docker builder cache..."
    docker builder prune -af 2>&1 | grep -E 'Total reclaimed|^deleted:' | tail -5 || true

    echo ""
    log_step "Cleaning apt package cache..."
    sudo apt-get clean >/dev/null 2>&1 || true
    log_success "Apt cache cleaned"

    echo ""
    log_step "Vacuuming system journals to 50MB..."
    sudo journalctl --vacuum-size=50M >/dev/null 2>&1 || true
    log_success "System journals trimmed"

    free_after=$(df -h / 2>/dev/null | awk 'NR == 2 { print $4 }')

    echo ""
    if [[ -n "$reclaimable" && "$reclaimable" != "0B" ]]; then
        log_success "Cleanup complete. Docker reported ${reclaimable} reclaimable before pruning."
    else
        log_success "Cleanup complete."
    fi
    log_info "Free space: ${free_before:-unknown} -> ${free_after:-unknown}"
}

prompt_for_post_install_cleanup() {
    [[ "${SETUP_MODE:-interactive}" == "interactive" ]] || return 0
    check_command docker || return 0

    local disk_usage disk_summary image_total reclaimable apt_cache journal_usage reclaimable_bytes
    disk_usage=$(get_root_disk_usage_percent)
    image_total=$(get_docker_image_total_human)
    reclaimable=$(get_docker_image_reclaimable_human)

    if ! should_offer_post_install_cleanup "$disk_usage" "$reclaimable"; then
        return 0
    fi

    disk_summary=$(get_root_disk_usage_summary)
    apt_cache=$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')
    journal_usage=$(journalctl --disk-usage 2>/dev/null | sed -n 's/.*take up \([0-9.]\+[A-Za-z]\+\).*/\1/p')
    reclaimable_bytes=$(human_size_to_bytes "$reclaimable")

    screen_title "Disk Cleanup" "WeekendStack is up. You can reclaim unused disk space now without touching running services."
    echo "  Root disk usage: ${disk_summary:-unknown}" >&2
    echo "  Docker images on disk: ${image_total:-unknown}" >&2
    echo "  Unused Docker images reclaimable now: ${reclaimable:-0B}" >&2
    if [[ -n "$apt_cache" ]]; then
        echo "  Apt cache: ${apt_cache}" >&2
    fi
    if [[ -n "$journal_usage" ]]; then
        echo "  System journals: ${journal_usage}" >&2
    fi
    echo "" >&2
    echo "  This cleanup keeps running containers, named volumes, and registry cache data." >&2
    echo "  Future rebuilds or profile changes may need to pull unused images again." >&2
    echo "" >&2

    if (( reclaimable_bytes >= 1000000000 )); then
        if ! prompt_yes_no "Reclaim space now?" "y"; then
            log_info "Keeping unused images and caches on disk"
            return 0
        fi
    else
        if ! prompt_yes_no "Run light cleanup anyway?" "n"; then
            log_info "Keeping current caches on disk"
            return 0
        fi
    fi

    run_post_install_cleanup
}
